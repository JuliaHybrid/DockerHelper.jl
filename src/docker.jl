using EasyMonad
import EasyMonad.(>>)
using Printf
using NestedVector
import NestedVector.(++)
using StringParser

include("path.jl")

abstract type Command end

struct Maintainer <: Command
    content::String
end
content(m::Maintainer)::String = @sprintf("MAINTAINER %s", m.content)

struct Copy <: Command
    from::Path 
    to::Path
    file::Path 
end

Copy(from::Path, to::Path) = begin 
    file = split(from.p, "/")[end] |> Path 
    return Copy(from, to, file)
end
content(c::Copy)::String = @sprintf("COPY %s %s", c.file.p, joinpath(c.to.p, c.file.p))

struct EnvAppend <: Command 
    content::String
end
content(e::EnvAppend)::String = @sprintf("ENV PATH=\${PATH}:%s", e.content)

struct Run <: Command 
    content::String
end
content(r::Run)::String = @sprintf("RUN %s", r.content)

struct Location <: Command
    area::String
    city::String
end
content(l::Location)::String = begin 
    location = @sprintf("%s/%s", l.area, l.city)
    command = @sprintf("echo %s > /etc/timezone && ln -snf /usr/share/zoneinfo/%s /etc/localtime", location, location)
    return Run(command) |> content
end

struct Apt <: Command 
    packages::Vector{String}
end
content(a::Apt)::String = begin 
    package_string = foldr((x, y)->@sprintf("%s %s", x, y), a.packages; init="")
    command = @sprintf("apt-get update && apt-get -y install %s && rm -rf /var/lib/apt/lists/*", package_string)
    return Run(command) |> content
end

struct Conda <: Command 
    packages::Vector{String}
end
content(c::Conda)::String = begin 
    package_string = foldr((x, y)->@sprintf("%s %s", x, y), c.packages; init="")
    command = @sprintf("conda install -y %s", package_string)
    return Run(command) |> content
end

struct Pip <: Command 
    packages::Vector{String}
end
content(p::Pip)::String = begin 
    package_string = foldr((x, y)->@sprintf("%s %s", x, y), p.packages; init="")
    command = @sprintf("pip install %s -i https://pypi.tuna.tsinghua.edu.cn/simple", package_string)
    return Run(command) |> content
end

struct JuliaAdd <: Command 
    type::Union{Val{:name}, Val{:url}, Val{:path}} 
    content::String
end
content(str::String, ::Val{:name}) = @sprintf("Pkg.add(name=\"%s\")", str)
content(str::String, ::Val{:url}) = @sprintf("Pkg.add(url=\"%s\")", str)
content(str::String, ::Val{:path}) = @sprintf("Pkg.add(path=\"%s\")", str)
content(j::JuliaAdd) = content(j.content, j.type)

abstract type ExtraCommand end

struct CopyOut <: ExtraCommand
    src::Path 
    dst::Path
    container_id::String
end

struct Builder 
    tag::String
    dep_tag::String
    dir::Path
    commands::Vector{Command}
    extracommands::Vector{ExtraCommand}
end
Builder(tag::String, dep_tag::String, dir::Path, commands::Vector{Command}) = Builder(tag, dep_tag, dir, commands, ExtraCommand[])


run_copy(c::Copy, b::Builder) = begin 
    pcopy(c.from, pjoin([b.dir, c.file]))
end
run_copy(cs::Vector{Command}, b::Builder) = begin 
    map(cs) do c 
        c isa Copy && run_copy(c, b)
    end
end
run_copy(b::Builder) = begin 
    run_copy(b.commands, b)
end

(filter_split!(vs::Vector{T}, pred::UnaryFunction{T, Bool}, result::Vector{Vector{T}})::Vector{Vector{T}}) where T = begin 
    length(vs)==0 && return result 
    x, xs = vs[1], vs[2:end]
    x >> pred && push!(result[1], x)
    !(x >> pred) && push!(result[2], x)
    return filter_split!(xs, pred, result)
end


(filter_split(vs::Vector{T}, pred::Function)::Vector{Vector{T}}) where T = begin 
    return filter_split!(vs, UnaryFunction{T, Bool}(pred), [T[], T[]])
end


build_dockerfile(B::Builder)::String = begin 
    dockerfile = "FROM " * B.dep_tag * "\n"
    commainds = reduce((++), filter_split(B.commands, x->x isa Maintainer))
    map(commainds) do c
        dockerfile *= content(c) * "\n"
    end 
    return dockerfile
end

build_dockerfile(B::Builder, ::Val{:deploy}) = begin 
    dockerfile_content = build_dockerfile(B)
    file_path = joinpath(B.dir.p, "Dockerfile")
    open(file_path, "w") do io
        write(io, dockerfile_content)
    end
end

get_tag_id()::Vector{Tuple{String, String}} = begin 
    result = open(`docker image ls`, "r", stdout) do io
        read(io, String)
    end
    result_lines = map(String, split(result, "\n"))

    parser = SepMulti(" ", nothing)
    table = map(result_lines) do x 
        if length(x)>0
            return Vector{String}(string_parse(x, parser).content)
        else 
            return nothing
        end
    end
    @assert table[1][1]=="REPOSITORY"
    tags = map(table[2:end]) do maybeAlist 
        maybeAlist >> maybeAlist -> (maybeAlist[1] * ":" * maybeAlist[2], maybeAlist[3])
    end
    tags_id = Vector{Tuple{String, String}}(filter(x->!(x isa Nothing), tags))
    # tags_id = Dict(map(x->x[1], tags_id) .=> map(x->x[2], tags_id))

    return tags_id
end
hash_tag_id(tags_id::Vector{Tuple{String, String}})::Dict{String, String} = Dict(map(x->x[1], tags_id) .=> map(x->x[2], tags_id))

is_tag_exist(tag::String)::Bool = begin 
    tags_id = get_tag_id()
    tags = map(t->t[1], tags_id)

    return tag in tags
end


get_container_info() = begin 
    result = open(`docker ps -a`, "r", stdout) do io
        read(io, String)
    end
    content = map(String, split(result, "\n"))
end

run_copyout(container_id::String, src::Path, dst::Path) = begin 
    @assert isdir(dst.p)
    srcp = src.p 
    dstp = dst.p
    file = split(srcp, "/")[end]
    command = `docker cp $container_id:$srcp $dstp`
    @show command
    target = joinpath(dstp, file)
    @show target, isdir(target) || isfile(target)
    !(isdir(target) || isfile(target)) && run(command)
end
run_copyout(b::Builder, c::CopyOut) = begin 
    src = c.src 
    dst = pjoin([b.dir, c.dst])
    run_copyout(c.container_id, src, dst)
end

run_copyout(B::Builder) = begin 
    map(B.extracommands) do command 
        command isa CopyOut && run_copyout(B, command)
        return nothing
    end
end


run_build(B::Builder) = begin 
    run_mkdir(B.dir)
    run_copyout(B)
    run_copy(B)
    build_dockerfile(B, Val(:deploy))
    tag = B.tag
    build_command = `docker build -t $tag .`
    !is_tag_exist(tag) && pcd_run(B.dir, build_command)
    @show pwd()
end
(B::Builder)() = run_build(B)

run_clean(B::Builder) = begin 
    tag = B.tag
    probe_path(B.dir) >> x->rm(x, force=true, recursive=true)
    if is_tag_exist(tag)
        tag_id_dict = hash_tag_id(get_tag_id())
        id = tag_id_dict[tag]
        clean_command = `docker image rm -f $id`
        run(clean_command)
    end
end

run_retag(B::Builder, prefix::String) = begin 
    tag = B.tag

    afix = split(tag, ":")[end]
    newtag = prefix * ":" * afix

    @assert !is_tag_exist(newtag)

    command = `docker tag $tag $newtag`
    run(command)
end

run_push(B::Builder, prefix::String) = begin 
    tag = B.tag

    afix = split(tag, ":")[end]
    newtag = prefix * ":" * afix

    @assert is_tag_exist(newtag)

    command = `docker push $newtag`
    run(command)
end