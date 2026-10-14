# Writing what a JLD2 file holds as a MATLAB file, through the JLD2 extension.

@testsnippet JLD2Files begin
    using Mate73
    using JLD2
    import MAT

    struct Limits
        lo::Float64
        hi::Float64
    end
    struct Cfg
        gain::Float64
        mode::Symbol
        steps::StepRangeLen{Float64, Base.TwicePrecision{Float64}, Base.TwicePrecision{Float64}, Int}
        limits::Limits
        runs::Vector{Limits}
    end

    "Convert the open JLD2 file `p` to a MATLAB file, and give back where it went."
    function tomat(p)
        out = splitext(p)[1] * ".mat"
        jldopen(f -> matwrite(out, f), p)
        return out
    end
end

@testitem "a JLD2 file of structs, Dicts and groups becomes a MATLAB file" setup = [JLD2Files] begin
    mktempdir() do dir
        p = joinpath(dir, "data.jld2")
        cfg = Cfg(2.5, :fast, 0.0:0.5:1.0, Limits(1.0, 10.0), [Limits(0.0, 1.0), Limits(2.0, 3.0)])
        jldsave(p; cfg, x = [1.0 2.0; 3.0 4.0], d = Dict("a" => 1, :b => "two"), t = (1.0, "xy"))
        jldopen(p, "a+") do f
            f["grp/sub"] = Int32(7)
        end
        out = tomat(p)

        for d in (matread(out), MAT.matread(out))
            @test d["x"] == [1.0 2.0; 3.0 4.0]
            @test d["cfg"]["mode"] == "fast"
            @test vec(d["cfg"]["steps"]) == [0.0, 0.5, 1.0]
            @test only(d["cfg"]["limits"]["hi"]) == 10.0
            @test only(d["cfg"]["runs"][2]["lo"]) == 2.0
            @test only(d["d"]["a"]) == 1
            @test d["d"]["b"] == "two"
            @test d["t"][2] == "xy"
            @test only(d["grp"]["sub"]) == 7
        end
    end
end

@testitem "a struct whose type is not defined is written from its fields" setup = [JLD2Files] begin
    mktempdir() do dir
        # A type in a module JLD2 cannot find again, so it loads JLD2's stand-in instead.
        gone = Module(:Gone)
        Core.eval(
            gone, :(
                struct Lim
                    lo::Float64; hi::Float64
                end
            )
        )
        p = joinpath(dir, "gone.jld2")
        jldsave(p; lim = Base.invokelatest(() -> gone.Lim(1.0, 2.0)))
        @test jldopen(f -> f["lim"], p) isa JLD2.ReconstructedStatic
        @test matread(tomat(p))["lim"]["hi"] == fill(2.0, 1, 1)
    end
end

@testitem "a value with no MATLAB form stops and says where it is" setup = [JLD2Files] begin
    mktempdir() do dir
        p = joinpath(dir, "bad.jld2")
        jldsave(p; cfg = (a = 1.0, z = [1.0 + 2.0im]))
        @test_throws "cannot write cfg.z(1): ComplexF64 has no MATLAB form" tomat(p)

        jldsave(p; n = (a = [1.0, 2.0], b = (nothing,)))
        @test_throws "cannot write n.b{1}: Nothing has no MATLAB form" tomat(p)

        jldsave(p; d = Dict(1 => 2.0))
        @test_throws "needs text keys, not Int64" tomat(p)
    end
end
