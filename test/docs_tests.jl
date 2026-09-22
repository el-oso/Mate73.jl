# The examples in README.md and docs/src/, run against files that hold what they describe.
#
# An example that does not run is worse than no example, so each one here is the code from the
# documentation, changed only where it has to name a file this setup built.

@testsnippet Examples begin
    using Mate73
    import MAT

    """
    Build the files the documentation opens: `results.mat` and `run.mat`.

    Nothing writes a MATLAB table, this package or MAT.jl, so the table example reads the
    fixture MATLAB itself wrote.
    """
    function docfiles(dir)
        matwrite(
            joinpath(dir, "results.mat"),
            "A" => [1.0 3.0; 4.0 2.0],
            "B" => reshape(collect(1.0:8.0), 2, 2, 2),
            "n" => Int64(42),
            "label" => "hello",
            "flags" => [true false],
            "cfg" => (gain = 2.5, mode = "fast"),
            "c" => (1.0, "two"),
            "s" => (a = [1.0 2.0], b = "text"),
        )
        matwrite(
            joinpath(dir, "run.mat"),
            "cfg" => (gain = 2.5, mode = "fast", limits = (1.0, 10.0)),
            "runs" => (
                [1.0 2.0],
                "second",
                (
                    count = 4.0, inner = (values = [1.0 2.0 3.0], extra = [11.0 12.0 13.0]),
                    parts = (name = ("first", "second"),), label = "run one",
                ),
            ),
        )
        return dir
    end
end

@testitem "the README opening examples" setup = [Examples] begin
    mktempdir() do dir
        docfiles(dir)
        cd(dir) do
            d = matread("results.mat")
            @test d["A"] == [1.0 3.0; 4.0 2.0]
            matwrite("out.mat", "A" => d["A"], "label" => "hello")
            @test matread("out.mat")["label"] == "hello"

            f = matopen("results.mat")
            @test "A" in keys(f)
            @test matsize(f, "A") == [2, 2]
            @test matread(f, "A") == [1.0 3.0; 4.0 2.0]
        end
    end
end

@testitem "the two ways to read, and the path form" setup = [Examples] begin
    mktempdir() do dir
        docfiles(dir)
        cd(dir) do
            f = matopen("results.mat")
            @test matread("results.mat") isa Dict
            @test matread(f, "A") == [1.0 3.0; 4.0 2.0]
            @test matread(f, "A", Matrix{Float64}) == [1.0 3.0; 4.0 2.0]
            @test matread("results.mat", "A", Matrix{Float64}) == [1.0 3.0; 4.0 2.0]
        end
    end
end

@testitem "every @matload form the docs show" setup = [Examples] begin
    mktempdir() do dir
        docfiles(dir)
        cd(dir) do
            # A path, opened once for the whole block.
            v = @matload "results.mat" begin
                A::Matrix{Float64}
                n::Int64
                label::String
                gain = "cfg/gain"::Float64
            end
            @test v.A == [1.0 3.0; 4.0 2.0]
            @test v.n === Int64(42)
            @test v.label == "hello"
            @test v.gain === 2.5

            # A file already open, and the one-line form.
            f = matopen("results.mat")
            @test (@matload f A::Matrix{Float64}).A == v.A
            w = @matload f begin
                A::Matrix{Float64}
                B::Array{Float64, 3}
                flags::Matrix{Bool}
            end
            @test size(w.B) == (2, 2, 2)
            @test w.flags == [true false]

            # Single numbers, and the 1x1 array when you want it.
            x = @matload f begin
                n::Int64
                gain = "cfg/gain"::Float64
                count = "n"::Matrix{Int64}
            end
            @test x.n === Int64(42)
            @test x.count == fill(Int64(42), 1, 1)
        end
    end
end

@testitem "the mark examples from the README and format page" setup = [Examples] begin
    mktempdir() do dir
        docfiles(dir)
        cd(dir) do
            f = matopen("results.mat")

            cells = matread(f, "c", Matrix{MatRef})
            @test matclass(f, cells[1]) == Mate73.MAT_DOUBLE
            @test matread(f, cells[1], Matrix{Float64}) == fill(1.0, 1, 1)
            @test sort(matkeys(f, "s")) == ["a", "b"]
            @test matread(f, "s/a", Matrix{Float64}) == [1.0 2.0]

            g = matopen("run.mat")
            runs = matread(g, "runs", Matrix{MatRef})
            one = runs[1, 3]
            @test matread(g, one, "count", Float64) === 4.0
            @test matread(g, one, "inner/values", Matrix{Float64}) == [1.0 2.0 3.0]
            @test matref(g, one, "inner") isa MatRef

            u = @matload g, one begin
                count = "count"::Float64
                values = "inner/values"::Matrix{Float64}
            end
            @test u.count === 4.0

            inner = matref(g, one, "inner")
            @test matread(g, inner, "values", Matrix{Float64}) == [1.0 2.0 3.0]
            @test matread(g, inner, "extra", Matrix{Float64}) == [11.0 12.0 13.0]

            names = matread(g, one, "parts/name", Matrix{MatRef})
            @test matread(g, names[1], String) == "first"
        end
    end
end

@testitem "the writing examples" setup = [Examples] begin
    mktempdir() do dir
        cd(dir) do
            matwrite("out.mat", "A" => rand(4, 4), "flags" => [true, false], "label" => "run 3")
            @test sort(collect(keys(matread("out.mat")))) == ["A", "flags", "label"]

            settings = (gain = 2.5, mode = "fast", limits = (1.0, 10.0))
            runs = ([1.0 2.0 3.0], "second run failed", (name = "third", ok = true))
            matwrite("run.mat", "cfg" => settings, "runs" => runs, "count" => 3)
            d = MAT.matread("run.mat")
            @test d["cfg"]["gain"] == 2.5
            @test d["cfg"]["limits"] == Any[1.0 10.0]
            @test d["runs"][3]["name"] == "third"

            w = MatWriter()
            for (name, value) in ["a" => 1.0, "b" => "two"]
                push!(w, name, value)
            end
            matwrite("loop.mat", w)
            @test matread("loop.mat", "b", String) == "two"

            # Write a result and read it back, both halves stating their types.
            matwrite("res.mat", "gain" => 2.5, "count" => Int64(7), "label" => "run 3")
            v = @matload "res.mat" begin
                gain::Float64
                count::Int64
                label::String
            end
            @test v == (gain = 2.5, count = Int64(7), label = "run 3")

            matwrite("cfg.mat", "cfg" => (gain = 2.5, mode = "fast"))
            c = @matload "cfg.mat" begin
                gain = "cfg/gain"::Float64
                mode = "cfg/mode"::String
            end
            @test c.mode == "fast"

            matwrite("cells.mat", "runs" => ([1.0 2.0], "second"))
            f = matopen("cells.mat")
            items = matread(f, "runs", Matrix{MatRef})
            @test matread(f, items[1], Matrix{Float64}) == [1.0 2.0]
            @test matread(f, items[2], String) == "second"
        end
    end
end

@testitem "the table examples" setup = [Fixtures] begin
    import Tables

    # The documentation calls the variable "flights"; this fixture calls it "s/testTable".
    # Nothing writes a MATLAB table, so the example has to read one MATLAB wrote.
    f = matopen(fixture("struct_table_datetime.mat"))
    t = matread(f, "s/testTable")
    @test t isa NamedTuple
    @test Tables.istable(t)
    @test Tables.columnnames(Tables.columns(t)) == keys(t)
    @test t.Customer == ["Jones", "Brown", "Smith"]

    typed = matread(
        f, "s/testTable",
        NamedTuple{(:FlightNum, :Customer), Tuple{Vector{Float64}, Vector{String}}},
    )
    @test typed.FlightNum == [1261.0, 547.0, 3489.0]
end

@testitem "the object and function-handle examples" setup = [Fixtures] begin
    f = matopen(fixture("user_defined_classdefs.mat"))
    @test matobjectclass(f, "obj_with_vals") == "TestClasses.BasicClass"
    @test sort(matkeys(f, "obj_with_vals")) == ["a", "b", "c"]
    @test matread(f, "obj_with_vals/a", Matrix{Float64}) isa Matrix{Float64}

    g = matopen(fixture("function_handles.mat"))
    @test matread(g, "sin/function_handle/function", String) == "sin"

    h = matopen(fixture("struct_table_datetime.mat"))
    @test matread(h, "s/testDatetime", Matrix{Mate73.DateTime}) isa Matrix
end
