using Pkg 
Pkg.activate(".")
using DockerHelper
import NestedVector.(++)

git() = begin 
    dep_tag = "ubuntu:18.04"
    tag = "le/git:test"
    maintain_info = Maintainer("le.niu@hotmail.com")

    run_commands = [
        Apt(["git",]),
    ]

    B = Builder(tag, dep_tag, Path(".build/git"), reduce((++), map(Vector{Command}, [[maintain_info, ], run_commands])))
    return B
end


B = git()
B()
# run_clean(B)