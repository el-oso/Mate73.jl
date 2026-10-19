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
        # Asked through a caller: on Julia 1.14 `return_types` on a generated method itself is `Any`.
        readcfg(f) = matread(f, "cfg", Settings)
        @test Base.return_types(readcfg, (typeof(f),)) == [Settings]

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
        @test ours isa Expr
        @test ours.head === :block
        @test all(d -> d isa Expr && d.head === :struct, ours.args)
        @test ours == theirs
        src = string(ours)
        @test occursin("gain::Float64", src)          # a 1x1 is a scalar
        @test occursin("runs::Matrix{CfgRuns}", src)
        @test occursin("name::String", src)           # MAT.jl's one-letter Char is text
        @test occursin("tags::Matrix{String}", src)
        @test occursin("mixed::Tuple{Matrix{Float64}, String}", src)

        nt = string(matstructs(sample(2.5), :Cfg))
        @test occursin("runs::Vector{CfgRuns}", nt)  # a tuple is a cell of one row
        @test occursin("tags::Vector{String}", nt)
    end
end

@testitem "tostruct converts a Dict or a NamedTuple into generated types" setup = [Template] begin
    mktempdir() do dir
        path = joinpath(dir, "t.mat")
        matwrite(path, "cfg" => sample(2.5))
        Base.eval(@__MODULE__, matstructs(matread(path)["cfg"], :DCfg))
        Base.eval(@__MODULE__, matstructs(sample(2.5), :NCfg))
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
        @eval convertn(x) = tostruct(NCfg, x)
        @test only(@invokelatest Base.return_types(convertn, (typeof(sample(2.5)),))) === NCfg
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
        @eval readrun(p) = matread(p, TRun)
        @test only(@invokelatest Base.return_types(readrun, (String,))) === TRun

        @test_throws "no variable or field named \"nope\"" @eval @matstructs X $template "nope"
    end
end

@testitem "@matstructs unwrap ignores the name of the only variable" setup = [Template] begin
    mktempdir() do dir
        # Each file wraps the struct in a name of its own, as `save` does in MATLAB.
        first = joinpath(dir, "run_2023.mat")
        second = joinpath(dir, "run_2024.mat")
        matwrite(first, "run_2023" => sample(1.0))
        matwrite(second, "run_2024" => sample(7.0))
        @eval @matstructs WCfg $first unwrap

        # The name of the template's own variable is in neither the type nor its fields.
        @test !occursin("run_2023", string(matstructs(matread(first)["run_2023"], :WCfg)))
        for (path, gain) in ((first, 1.0), (second, 7.0))
            f = matopen(path)
            cfg = @invokelatest matread(f, only(keys(f)), WCfg)
            @test cfg.gain == gain
            @test cfg.limits.hi == 10 * gain
        end

        two = joinpath(dir, "two.mat")
        matwrite(two, "a" => sample(1.0), "b" => sample(2.0))
        @test_throws "nothing to unwrap" @eval @matstructs Y $two unwrap
        @test_throws "as a string literal, or `unwrap`" @eval @matstructs Z $first other
    end
end

@testitem "a field no template describes is left out, and said so" setup = [Template] begin
    mktempdir() do dir
        path = joinpath(dir, "t.mat")
        matwrite(
            path,
            "cfg" => Dict{String, Any}(
                "gain" => 2.5,
                "opt" => Dict{String, Any}(),            # a struct with no fields
                "notes" => Matrix{Any}(undef, 0, 0),     # an empty cell
                "blank" => Float64[],                    # an empty array of numbers
            ),
        )
        d = matread(path)["cfg"]
        # Nothing to take a type from, so no field is written and a warning names it.
        src = string(@test_logs (:warn, r"does not name notes, opt") matstructs(d, :OCfg))
        @test !occursin("opt::", src)
        @test !occursin("notes::", src)
        # An empty array of numbers does carry its own type, so it is described.
        @test occursin("blank::", src)
        @test occursin("gain::Float64", src)

        @test_logs (:warn, r"does not name notes, opt") @eval @matstructs OCfg2 $path "cfg"
        @test @eval(fieldnames(OCfg2)) == (:blank, :gain)
    end
end

@testitem "several templates are merged into one set of types" setup = [Template] begin
    mktempdir() do dir
        # The same layout in both files, but each is empty where the other is filled.
        a = joinpath(dir, "a.mat")
        b = joinpath(dir, "b.mat")
        matwrite(
            a,
            "run" => Dict{String, Any}(
                "gain" => 2.5, "label" => "a", "opt" => Dict{String, Any}(), "only_a" => 1.0,
            ),
        )
        matwrite(b, "run" => (gain = 3.0, label = "b", opt = (lo = 1.0, hi = 2.0)))
        @test_logs (:warn, r"does not name only_a, opt") @eval @matstructs MRun [$a, $b] "run"

        # `only_a` is in one file and `opt` is empty in one, so neither is named. Both files
        # then read into the type, which is the point of giving more than one template.
        @test @eval(fieldnames(MRun)) == (:gain, :label)
        for (path, gain) in ((a, 2.5), (b, 3.0))
            f = matopen(path)
            @test (@invokelatest matread(f, "run", MRun)).gain == gain
        end

        # One template on its own cannot know that `opt` is ever empty.
        @eval @matstructs BRun $b "run"
        @test :opt in @eval(fieldnames(BRun))

        # A field with two different shapes cannot have one type.
        c = joinpath(dir, "c.mat")
        matwrite(c, "run" => (gain = [1.0 2.0], label = "c"))
        @test_throws "disagree about \"gain\"" @eval @matstructs CRun [$a, $c] "run"

        @test_throws "give at least one template" @eval @matstructs NRun [] "run"
        @test_throws "a list of them" @eval @matstructs XRun 42 "run"
    end
end

@testitem "empty cells read back, from either writer, as a Dict or typed" setup = [Template] begin
    mktempdir() do dir
        cfg = Dict{String, Any}("gain" => 2.5, "notes" => Any[], "tags" => String[], "items" => Any[Any[], "x"])
        for (w, write) in (
                ("ours", p -> matwrite(p, Dict{String, Any}("cfg" => cfg))),
                ("MAT", p -> MAT.matwrite(p, Dict{String, Any}("cfg" => cfg); compress = false)),
            )
            p = joinpath(dir, w * ".mat")
            write(p)
            # This package keeps an empty Vector at rank 1; MAT.jl gives an empty cell no storage.
            d = matread(p)["cfg"]
            @test d["notes"] == Any[] && d["notes"] isa Vector{Any}
            @test d["items"][2] == "x"
            f = matopen(p)
            @test matread(f, "cfg/items", Tuple{Vector{Any}, String}) == (Any[], "x")
            @test matread(f, "cfg/notes", Vector{Any}) == Any[]
        end
    end
end

@testitem "@matstructs takes a path into the template" setup = [Template] begin
    mktempdir() do dir
        template = joinpath(dir, "template.mat")
        today = joinpath(dir, "today.mat")
        matwrite(template, "cfg" => sample(1.0))
        matwrite(today, "cfg" => sample(7.0))
        # A field of a variable, and one item of a cell array of structs.
        @eval @matstructs PLim $template "cfg/limits"
        @eval @matstructs PRun $template "cfg/runs/1"
        @test @eval(fieldnames(PLim)) == (:hi, :lo)
        @test @eval(fieldnames(PRun)) == (:name, :ok)

        f = matopen(today)
        @test (@invokelatest matread(f, "cfg/limits", PLim)).hi == 70.0
        # The items of a cell share a shape, so the type written from one reads any of them.
        @test (@invokelatest matread(f, "cfg/runs/2", PRun)).name == "b"
        @test (@invokelatest matread(f, "cfg/runs", Matrix{PRun}))[1].ok

        @test_throws "no variable or field named" @eval @matstructs PX $template "cfg/nope"
        @test_throws "is not a struct, so it has no fields" @eval(
            @matstructs PY $template "cfg/gain"
        )
    end
end
