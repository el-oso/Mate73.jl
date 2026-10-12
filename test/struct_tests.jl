# Reading into types of your own: structs, tuples and arrays of structs, nested.

@testsnippet Records begin
    using Mate73
    const FIXTURES = joinpath(@__DIR__, "fixtures", "v7.3")
    fixture(name) = joinpath(FIXTURES, name)

    struct Limits
        lo::Float64
        hi::Float64
    end
    struct Settings
        gain::Float64
        mode::String
        n::Int32
        weights::Matrix{Float64}
        limits::Limits
    end

    # The default `==` on a struct compares array fields by identity, so compare by value.
    same(a, b) = a == b
    same(a::T, b::T) where {T} = isstructtype(T) && !(a isa AbstractArray) ?
        all(k -> same(getfield(a, k), getfield(b, k)), fieldnames(T)) : a == b
    same(a::AbstractArray, b::AbstractArray) = size(a) == size(b) && all(map(same, a, b))
end

@testitem "a nested struct reads into nested types" setup = [Records] begin
    mktempdir() do dir
        path = joinpath(dir, "cfg.mat")
        matwrite(
            path,
            "cfg" => (
                gain = 2.5, mode = "fast", n = Int32(7), weights = [1.0 2.0],
                limits = (lo = 1.0, hi = 10.0), unused = "left unread",
            ),
        )
        f = matopen(path)
        s = matread(f, "cfg", Settings)
        @test same(s, Settings(2.5, "fast", Int32(7), [1.0 2.0], Limits(1.0, 10.0)))
        @test Base.return_types(matread, (typeof(f), String, Type{Settings})) == [Settings]

        # The macro writes the same typed read.
        v = @matload f cfg::Settings
        @test v.cfg.limits.hi == 10.0

        @test_throws "no variable or field named \"lo\"" matread(f, "cfg", Limits)
    end
end

@testitem "a cell reads into a tuple or an array of structs" setup = [Records] begin
    mktempdir() do dir
        path = joinpath(dir, "cells.mat")
        matwrite(
            path,
            "runs" => ([1.0 2.0], "second", (lo = 3.0, hi = 4.0)),
            "lims" => ((lo = 1.0, hi = 2.0), (lo = 3.0, hi = 4.0)),
        )
        f = matopen(path)
        @test matread(f, "runs", Tuple{Matrix{Float64}, String, Limits}) ==
            ([1.0 2.0], "second", Limits(3.0, 4.0))
        @test_throws "has 3 items, not 2" matread(f, "runs", Tuple{Matrix{Float64}, String})

        lims = matread(f, "lims", Matrix{Limits})
        @test same(lims, [Limits(1.0, 2.0) Limits(3.0, 4.0)])
        @test Base.return_types(matread, (typeof(f), String, Type{Matrix{Limits}})) ==
            [Matrix{Limits}]
    end
end

@testitem "a MATLAB struct array reads into an array of structs" setup = [Records] begin
    struct OnlyA
        a::Matrix{Float64}
    end
    struct ABC
        a::Matrix{Float64}
        b::Matrix{Float64}
        c::Matrix{Float64}
    end
    f = matopen(fixture("struct.mat"))
    # `s2` is a 1x2 struct array, written by MATLAB.
    @test same(matread(f, "s2", Matrix{OnlyA}), [OnlyA(fill(1.0, 1, 1)) OnlyA(fill(2.0, 1, 1))])
    # A single struct is a 1x1 struct array.
    @test same(
        matread(f, "s", Matrix{ABC}),
        reshape([ABC(fill(1.0, 1, 1), [1.0 2.0], [1.0 2.0 3.0])], 1, 1),
    )
end

@testitem "MATLAB objects read into structs, nested" setup = [Records] begin
    struct Inner
        a::Float64
        b::String
        c::Matrix{Float64}
    end
    struct Wrap
        InnerProp::Inner
    end
    struct Nested
        a::Inner
        c::Wrap
    end
    f = matopen(fixture("user_defined_classdefs.mat"))
    n = matread(f, "obj_with_nested_props", Nested)
    @test n.a.b == "Obj1"
    @test n.c.InnerProp.a == 2.0
    @test n.c.InnerProp.b == "Obj2"
end

@testitem "a type with no read stops with an error" setup = [Records] begin
    f = matopen(fixture("struct.mat"))
    @test_throws "has no read for it" matread(f, "s", Any)
end

@testitem "a cell of one row reads into a Vector of structs" setup = [Records] begin
    mktempdir() do dir
        path = joinpath(dir, "row.mat")
        matwrite(path, "lims" => ((lo = 1.0, hi = 2.0), (lo = 3.0, hi = 4.0)))
        @test same(matread(matopen(path), "lims", Vector{Limits}), [Limits(1.0, 2.0), Limits(3.0, 4.0)])
    end
end

@testitem "@matstruct renames, defaults, optional fields and paths" setup = [Records] begin
    @matstruct struct Lim
        lo = "lower"::Float64
        hi = "upper"::Float64
    end
    @matstruct struct Cfg
        gain::Float64
        mode::String = "fast"
        lims::Vector{Lim}
        weights::Union{Nothing, Matrix{Float64}}
        blank::Union{Nothing, Matrix{Float64}}
        offset = "calib/offset"::Float64
        scale = "calib/scale"::Float64 = 1.0
    end

    mktempdir() do dir
        path = joinpath(dir, "cfg.mat")
        matwrite(
            path,
            "cfg" => (
                gain = 2.5, blank = zeros(0, 0), calib = (offset = 0.5,),
                lims = ((lower = 1.0, upper = 2.0), (lower = 3.0, upper = 4.0)),
            ),
        )
        f = matopen(path)
        c = matread(f, "cfg", Cfg)
        @test c.gain == 2.5
        @test c.mode == "fast"              # absent: the default
        @test same(c.lims, [Lim(1.0, 2.0), Lim(3.0, 4.0)])
        @test isnothing(c.weights)          # absent and optional
        @test isnothing(c.blank)            # empty and optional
        @test c.offset == 0.5               # a path into a nested struct
        @test c.scale == 1.0                # absent along a path: the default
        @test Base.return_types(matread, (typeof(f), String, Type{Cfg})) == [Cfg]
        @test (@matload f cfg::Cfg).cfg.lims[2].hi == 4.0

        @test_throws "no variable or field named \"lower\"" matread(f, "cfg/calib", Lim)
    end
end

@testitem "@matstruct reads a MATLAB struct array and objects" setup = [Records] begin
    @matstruct struct OnlyA
        a::Matrix{Float64}
    end
    @matstruct struct Inner
        value = "a"::Float64
        label = "b"::String
    end
    @test same(
        matread(matopen(fixture("struct.mat")), "s2", Vector{OnlyA}),
        [OnlyA(fill(1.0, 1, 1)), OnlyA(fill(2.0, 1, 1))],
    )
    inner = matread(matopen(fixture("user_defined_classdefs.mat")), "obj_with_nested_props/c/InnerProp", Inner)
    @test inner.value == 2.0
    @test inner.label == "Obj2"
end

@testitem "@matstruct refuses a line it cannot read" begin
    using Mate73
    @test_throws "cannot read the line" Mate73.matfield(:(x + 1))
end

@testsnippet Template begin
    using Mate73
    import MAT
    "A nested result whose values depend on `g`, so two files share a shape but not values."
    sample(g) = (
        gain = g, mode = "fast", n = Int32(3), w = [1.0 2.0; 3.0 4.0],
        limits = (lo = 1.0, hi = 10g), mixed = ([1.0 2.0], "text"),
        runs = ((name = "a", ok = true), (name = "b", ok = false)), tags = ("x", "y", "z"),
    )
end

@testitem "matstructs writes the same types from either reader's Dict" setup = [Template] begin
    mktempdir() do dir
        path = joinpath(dir, "t.mat")
        matwrite(path, "cfg" => sample(2.5))
        ours = matstructs(matread(path)["cfg"], :Cfg)
        theirs = matstructs(MAT.matread(path)["cfg"], :Cfg)
        @test ours == theirs
        @test occursin("gain::Float64", ours)          # a 1x1 is a scalar
        @test occursin("runs::Matrix{CfgRuns}", ours)
        @test occursin("name::String", ours)           # MAT.jl's one-letter Char is text
        @test occursin("tags::Matrix{String}", ours)
        @test occursin("mixed::Tuple{Matrix{Float64}, String}", ours)

        nt = matstructs(sample(2.5), :Cfg)
        @test occursin("runs::Vector{CfgRuns}", nt)  # a tuple is a cell of one row
        @test occursin("tags::Vector{String}", nt)
    end
end

@testitem "tostruct converts a Dict or a NamedTuple into generated types" setup = [Template] begin
    mktempdir() do dir
        path = joinpath(dir, "t.mat")
        matwrite(path, "cfg" => sample(2.5))
        Base.include_string(@__MODULE__, matstructs(matread(path)["cfg"], :DCfg))
        Base.include_string(@__MODULE__, matstructs(sample(2.5), :NCfg))
        for d in (matread(path)["cfg"], MAT.matread(path)["cfg"])
            s = @invokelatest tostruct(DCfg, d)
            @test s.gain == 2.5
            @test s.limits.hi == 25.0
            @test s.runs[2].name == "b"
            @test s.tags == ["x" "y" "z"]
        end
        n = @invokelatest tostruct(NCfg, sample(2.5))
        @test n.runs[1].ok
        @test n.tags == ["x", "y", "z"]
        @test only(@invokelatest Base.return_types(tostruct, (Type{NCfg}, typeof(sample(2.5))))) === NCfg
    end
end

@testitem "a cell of text or numbers reads into a typed array" setup = [Template] begin
    mktempdir() do dir
        path = joinpath(dir, "cells.mat")
        matwrite(path, "tags" => ("x", "y"), "nums" => (1.0, 2.0))
        f = matopen(path)
        @test matread(f, "tags", Matrix{String}) == ["x" "y"]
        @test matread(f, "tags", Vector{String}) == ["x", "y"]
        @test matread(f, "nums", Matrix{Float64}) == [1.0 2.0]
    end
end

@testitem "@matstructs reads files shaped like a template" setup = [Template] begin
    mktempdir() do dir
        template = joinpath(dir, "template.mat")
        today = joinpath(dir, "today.mat")
        matwrite(template, "cfg" => sample(1.0), "count" => 3, "label" => "template")
        matwrite(today, "cfg" => sample(7.0), "count" => 9, "label" => "today")
        # `@eval` so the macro runs after the template exists.
        @eval @matstructs TCfg $template "cfg"
        @eval @matstructs TRun $template

        cfg = @invokelatest matread(matopen(today), "cfg", TCfg)
        @test cfg.gain == 7.0
        @test cfg.limits.hi == 70.0
        @test cfg.runs[2].name == "b"
        run = @invokelatest matread(today, TRun)
        @test run.label == "today"
        @test run.count == 9
        @test run.cfg.limits.hi == 70.0
        @test only(@invokelatest Base.return_types(matread, (String, Type{TRun}))) === TRun

        @test_throws "has no variable \"nope\"" @eval @matstructs X $template "nope"
    end
end
