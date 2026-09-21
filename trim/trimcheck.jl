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
            using MatteSeven
            # The macro expands to ordinary typed reads, so a function that uses it must
            # verify like any other. This is the root that proves it.
            #
            # `@eval` because the whole init block is expanded before `using` runs, so the
            # macro is not known yet at that point.
            @eval function loadfields(f::MatteSeven.MatFile)
                return MatteSeven.@matload f begin
                    a::Matrix{Float64}
                    n::Int64
                    label::String
                    gain = "cfg/gain"::Float64
                end
            end
            # The same block given a path rather than an open file.
            @eval function loadfrompath(path::String)
                return MatteSeven.@matload path begin
                    a::Matrix{Float64}
                    label::String
                end
            end
            # The same block starting at a mark rather than at the top of the file.
            @eval function loadbelow(f::MatteSeven.MatFile, r::MatteSeven.MatRef)
                return MatteSeven.@matload f, r begin
                    count = "count"::Float64
                    values = "inner/values"::Matrix{Float64}
                    label = "label"::String
                end
            end
        end,
        Main.loadfields(MatteSeven.MatFile),
        Main.loadfrompath(String),
        Main.loadbelow(MatteSeven.MatFile, MatteSeven.MatRef),
        MatteSeven.matref(MatteSeven.MatFile, MatteSeven.MatRef, String),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, String, Type{Float64}),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, String, Type{Matrix{Float64}}),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, String, Type{String}),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, String, Type{Matrix{MatteSeven.MatRef}}),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, String, Type{Matrix{MatteSeven.DateTime}}),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, String, Type{Matrix{String}}),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, String, Type{Array{Char, 2}}),
        MatteSeven.matopen(String),
        MatteSeven.matread(String, String, Type{Matrix{Float64}}),
        MatteSeven.matread(String, String, Type{String}),
        MatteSeven.matsize(MatteSeven.MatFile, String),
        MatteSeven.matclass(MatteSeven.MatFile, String),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Float64}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Matrix{Float64}}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Array{Float64, 3}}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Matrix{Float32}}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Matrix{Int32}}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Matrix{UInt8}}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Matrix{Bool}}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Matrix{ComplexF64}}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{String}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Matrix{MatteSeven.DateTime}}),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Matrix{String}}),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, Type{Matrix{String}}),
        MatteSeven.matread(
            MatteSeven.MatFile, String,
            Type{NamedTuple{(:a, :b), Tuple{Vector{Float64}, Vector{String}}}},
        ),
        MatteSeven.matread(MatteSeven.MatFile, String, Type{Matrix{MatteSeven.MatRef}}),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, Type{Matrix{Float64}}),
        MatteSeven.matread(MatteSeven.MatFile, MatteSeven.MatRef, Type{String}),
        MatteSeven.matclass(MatteSeven.MatFile, MatteSeven.MatRef),
        MatteSeven.matsize(MatteSeven.MatFile, MatteSeven.MatRef),
        MatteSeven.matkeys(MatteSeven.MatFile, String),
        MatteSeven.matobjectclass(MatteSeven.MatFile, String),
        Base.push!(MatteSeven.MatWriter, String, Matrix{Float64}),
        Base.push!(MatteSeven.MatWriter, String, Matrix{Bool}),
        Base.push!(MatteSeven.MatWriter, String, Float64),
        Base.push!(MatteSeven.MatWriter, String, String),
        # A struct and a cell, each holding the other, so the nesting is verified too.
        Base.push!(
            MatteSeven.MatWriter, String,
            NamedTuple{
                (:gain, :label, :items),
                Tuple{Float64, String, Tuple{Float64, Matrix{Float64}}},
            },
        ),
        Base.push!(
            MatteSeven.MatWriter, String,
            Tuple{Matrix{Float64}, String, NamedTuple{(:n,), Tuple{Int64}}},
        ),
        MatteSeven.matwrite(String, MatteSeven.MatWriter),
    )
end
