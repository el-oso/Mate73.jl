# Static half of the trim gate: run the `--trim=safe` verifier over every entry point.
#
# It has its own environment: TrimCheck pins the `Compiler` stdlib, which the test
# environment has no reason to carry.
#
# Run as: julia --project=trim trim/trimcheck.jl
#
# TrimCheck runs the same verifier pass a real build runs, so a failure here is a failure of
# the build too. It neither links nor runs, which is what `juliac/build.jl` adds.

using Test
using TrimCheck


@testset "entry points are trim-safe" begin
    @validate(
        init = begin
            using Mate73
            # The macro expands to ordinary typed reads, so a function that uses it must
            # verify like any other. This is the root that proves it.
            #
            # `@eval` because the whole init block is expanded before `using` runs, so the
            # macro is not known yet at that point.
            @eval function loadfields(f::Mate73.MatFile)
                return Mate73.@matload f begin
                    a::Matrix{Float64}
                    n::Int64
                    label::String
                    gain = "cfg/gain"::Float64
                end
            end
            # The same block given a path rather than an open file.
            @eval function loadfrompath(path::String)
                return Mate73.@matload path begin
                    a::Matrix{Float64}
                    label::String
                end
            end
            # The same block starting at a mark rather than at the top of the file.
            @eval function loadbelow(f::Mate73.MatFile, r::Mate73.MatRef)
                return Mate73.@matload f, r begin
                    count = "count"::Float64
                    values = "inner/values"::Matrix{Float64}
                    label = "label"::String
                end
            end
        end,
        Main.loadfields(Mate73.MatFile),
        Main.loadfrompath(String),
        Main.loadbelow(Mate73.MatFile, Mate73.MatRef),
        Mate73.matref(Mate73.MatFile, Mate73.MatRef, String),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, String, Type{Float64}),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, String, Type{Matrix{Float64}}),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, String, Type{String}),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, String, Type{Matrix{Mate73.MatRef}}),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, String, Type{Matrix{Mate73.DateTime}}),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, String, Type{Matrix{String}}),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, String, Type{Array{Char, 2}}),
        Mate73.matopen(String),
        Mate73.matread(String, String, Type{Matrix{Float64}}),
        Mate73.matread(String, String, Type{String}),
        Mate73.matsize(Mate73.MatFile, String),
        Mate73.matclass(Mate73.MatFile, String),
        Mate73.matread(Mate73.MatFile, String, Type{Float64}),
        Mate73.matread(Mate73.MatFile, String, Type{Matrix{Float64}}),
        Mate73.matread(Mate73.MatFile, String, Type{Array{Float64, 3}}),
        Mate73.matread(Mate73.MatFile, String, Type{Matrix{Float32}}),
        Mate73.matread(Mate73.MatFile, String, Type{Matrix{Int32}}),
        Mate73.matread(Mate73.MatFile, String, Type{Matrix{UInt8}}),
        Mate73.matread(Mate73.MatFile, String, Type{Matrix{Bool}}),
        Mate73.matread(Mate73.MatFile, String, Type{Matrix{ComplexF64}}),
        Mate73.matread(Mate73.MatFile, String, Type{String}),
        Mate73.matread(Mate73.MatFile, String, Type{Matrix{Mate73.DateTime}}),
        Mate73.matread(Mate73.MatFile, String, Type{Matrix{String}}),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, Type{Matrix{String}}),
        Mate73.matread(
            Mate73.MatFile, String,
            Type{NamedTuple{(:a, :b), Tuple{Vector{Float64}, Vector{String}}}},
        ),
        Mate73.matread(Mate73.MatFile, String, Type{Matrix{Mate73.MatRef}}),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, Type{Matrix{Float64}}),
        Mate73.matread(Mate73.MatFile, Mate73.MatRef, Type{String}),
        Mate73.matclass(Mate73.MatFile, Mate73.MatRef),
        Mate73.matsize(Mate73.MatFile, Mate73.MatRef),
        Mate73.matkeys(Mate73.MatFile, String),
        Mate73.matobjectclass(Mate73.MatFile, String),
        Base.push!(Mate73.MatWriter, String, Matrix{Float64}),
        Base.push!(Mate73.MatWriter, String, Matrix{Bool}),
        Base.push!(Mate73.MatWriter, String, Float64),
        Base.push!(Mate73.MatWriter, String, String),
        # A struct and a cell, each holding the other, so the nesting is verified too.
        Base.push!(
            Mate73.MatWriter, String,
            NamedTuple{
                (:gain, :label, :items),
                Tuple{Float64, String, Tuple{Float64, Matrix{Float64}}},
            },
        ),
        Base.push!(
            Mate73.MatWriter, String,
            Tuple{Matrix{Float64}, String, NamedTuple{(:n,), Tuple{Int64}}},
        ),
        Mate73.matwrite(String, Mate73.MatWriter),
    )
end
