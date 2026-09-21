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
            using MATTE73
            # The macro expands to ordinary typed reads, so a function that uses it must
            # verify like any other. This is the root that proves it.
            #
            # `@eval` because the whole init block is expanded before `using` runs, so the
            # macro is not known yet at that point.
            @eval function loadfields(f::MATTE73.MatFile)
                return MATTE73.@matload f begin
                    a::Matrix{Float64}
                    n::Int64
                    label::String
                    gain = "cfg/gain"::Float64
                end
            end
            # The same block given a path rather than an open file.
            @eval function loadfrompath(path::String)
                return MATTE73.@matload path begin
                    a::Matrix{Float64}
                    label::String
                end
            end
            # The same block starting at a mark rather than at the top of the file.
            @eval function loadbelow(f::MATTE73.MatFile, r::MATTE73.MatRef)
                return MATTE73.@matload f, r begin
                    count = "count"::Float64
                    values = "inner/values"::Matrix{Float64}
                    label = "label"::String
                end
            end
        end,
        Main.loadfields(MATTE73.MatFile),
        Main.loadfrompath(String),
        Main.loadbelow(MATTE73.MatFile, MATTE73.MatRef),
        MATTE73.matref(MATTE73.MatFile, MATTE73.MatRef, String),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, String, Type{Float64}),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, String, Type{Matrix{Float64}}),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, String, Type{String}),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, String, Type{Matrix{MATTE73.MatRef}}),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, String, Type{Matrix{MATTE73.DateTime}}),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, String, Type{Matrix{String}}),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, String, Type{Array{Char, 2}}),
        MATTE73.matopen(String),
        MATTE73.matread(String, String, Type{Matrix{Float64}}),
        MATTE73.matread(String, String, Type{String}),
        MATTE73.matsize(MATTE73.MatFile, String),
        MATTE73.matclass(MATTE73.MatFile, String),
        MATTE73.matread(MATTE73.MatFile, String, Type{Float64}),
        MATTE73.matread(MATTE73.MatFile, String, Type{Matrix{Float64}}),
        MATTE73.matread(MATTE73.MatFile, String, Type{Array{Float64, 3}}),
        MATTE73.matread(MATTE73.MatFile, String, Type{Matrix{Float32}}),
        MATTE73.matread(MATTE73.MatFile, String, Type{Matrix{Int32}}),
        MATTE73.matread(MATTE73.MatFile, String, Type{Matrix{UInt8}}),
        MATTE73.matread(MATTE73.MatFile, String, Type{Matrix{Bool}}),
        MATTE73.matread(MATTE73.MatFile, String, Type{Matrix{ComplexF64}}),
        MATTE73.matread(MATTE73.MatFile, String, Type{String}),
        MATTE73.matread(MATTE73.MatFile, String, Type{Matrix{MATTE73.DateTime}}),
        MATTE73.matread(MATTE73.MatFile, String, Type{Matrix{String}}),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, Type{Matrix{String}}),
        MATTE73.matread(
            MATTE73.MatFile, String,
            Type{NamedTuple{(:a, :b), Tuple{Vector{Float64}, Vector{String}}}},
        ),
        MATTE73.matread(MATTE73.MatFile, String, Type{Matrix{MATTE73.MatRef}}),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, Type{Matrix{Float64}}),
        MATTE73.matread(MATTE73.MatFile, MATTE73.MatRef, Type{String}),
        MATTE73.matclass(MATTE73.MatFile, MATTE73.MatRef),
        MATTE73.matsize(MATTE73.MatFile, MATTE73.MatRef),
        MATTE73.matkeys(MATTE73.MatFile, String),
        MATTE73.matobjectclass(MATTE73.MatFile, String),
        Base.push!(MATTE73.MatWriter, String, Matrix{Float64}),
        Base.push!(MATTE73.MatWriter, String, Matrix{Bool}),
        Base.push!(MATTE73.MatWriter, String, Float64),
        Base.push!(MATTE73.MatWriter, String, String),
        # A struct and a cell, each holding the other, so the nesting is verified too.
        Base.push!(
            MATTE73.MatWriter, String,
            NamedTuple{
                (:gain, :label, :items),
                Tuple{Float64, String, Tuple{Float64, Matrix{Float64}}},
            },
        ),
        Base.push!(
            MATTE73.MatWriter, String,
            Tuple{Matrix{Float64}, String, NamedTuple{(:n,), Tuple{Int64}}},
        ),
        MATTE73.matwrite(String, MATTE73.MatWriter),
    )
end
