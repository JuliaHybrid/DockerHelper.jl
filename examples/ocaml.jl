using DockerHelper

ocaml() = begin 
    dep_tag = "ubuntu:18.04"
    tag = "le/ocaml:5.0.0"
    maintain_info = Maintainer("le.niu@xtalpi.com")


    run_commands = [
        Location("Asia", "Shanghai"),
        Apt(["software-properties-common", "build-essential"]),
        Run("add-apt-repository ppa:avsm/ppa -y"),
        Apt(["opam",]),
        Run("opam init --disable-sandboxing --yes"),
        Run("opam update && opam switch create 5.0.0"),
        Run("eval \$(opam env --switch=5.0.0)")
        
    ]

    B = Builder(tag, dep_tag, Path("ocaml"), reduce((++), map(Vector{Command}, [[maintain_info, ], run_commands])))
    return B
end


B = ocaml()
run_build(B)
# run_clean(B)