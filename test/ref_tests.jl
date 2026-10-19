# Typed reads below a mark. A cell array and a struct array both hand out marks rather than
# values, so a path has to be able to start at one instead of at the top of the file.

@testsnippet Marks begin
    using Mate73
    import MAT

    """
    A file holding a 1x2 cell of structs, each with a nested struct and a cell of text.

    MAT.jl writes it, so the bytes come from the HDF5 C library rather than from this package.
    Scalars are 1x1 arrays, which is the shape MATLAB gives them.
    """
    function markfile(dir)
        path = joinpath(dir, "runs.mat")
        entry(n, values, names, label) = Dict{String, Any}(
            "count" => fill(n, 1, 1),
            "inner" => Dict{String, Any}("values" => values, "extra" => values .+ 10.0),
            "parts" => Dict{String, Any}("name" => names, "size" => fill(0.5, 1, 1)),
            "label" => label,
        )
        MAT.matwrite(
            path,
            Dict{String, Any}(
                "runs" => Any[
                entry(4.0, [1.0 2.0 3.0], Any["first" "second"], "run one") entry(
                    7.0, [9.0 8.0], Any["only"], "run two",
                )
                ],
            ),
        )
        return path
    end
end

@testitem "a number one step below a mark" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        runs = matread(f, "runs", Matrix{MatRef})
        @test size(runs) == (1, 2)
        @test matread(f, runs[1, 1], "count", Float64) === 4.0
        @test matread(f, runs[1, 2], "count", Float64) === 7.0
        # The same field as the 1x1 array the file really holds.
        @test matread(f, runs[1, 1], "count", Matrix{Float64}) == fill(4.0, 1, 1)
    end
end

@testitem "a path goes down more than one step below a mark" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        one = matread(f, "runs", Matrix{MatRef})[1, 1]
        @test matread(f, one, "inner/values", Matrix{Float64}) == [1.0 2.0 3.0]
        @test matread(f, one, "inner/extra", Matrix{Float64}) == [11.0 12.0 13.0]
        @test matread(f, one, "parts/size", Float64) === 0.5
    end
end

@testitem "a cell field below a mark hands out further marks" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        one = matread(f, "runs", Matrix{MatRef})[1, 1]
        names = matread(f, one, "parts/name", Matrix{MatRef})
        @test size(names) == (1, 2)
        @test matread(f, names[1], String) == "first"
        @test matread(f, names[2], String) == "second"
    end
end

@testitem "text below a mark" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        one = matread(f, "runs", Matrix{MatRef})[1, 1]
        @test matread(f, one, "label", String) == "run one"
    end
end

@testitem "matref steps down without reading" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        one = matread(f, "runs", Matrix{MatRef})[1, 1]
        inner = matref(f, one, "inner")
        @test inner isa MatRef
        # Field order is the file's, not MATLAB's, so only the set of names is checked.
        @test sort(matkeys(f, inner)) == ["extra", "values"]
        @test matread(f, inner, "values", Matrix{Float64}) == [1.0 2.0 3.0]
    end
end

@testitem "a name that is not there below a mark stops with an error" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        one = matread(f, "runs", Matrix{MatRef})[1, 1]
        @test_throws "\"nope\"" matread(f, one, "nope", Float64)
        @test_throws "\"inner/nope\"" matread(f, one, "inner/nope", Matrix{Float64})
    end
end

@testitem "the type checks below a mark are the ones above it" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        one = matread(f, "runs", Matrix{MatRef})[1, 1]
        @test_throws "rank 2, not 3" matread(f, one, "inner/values", Array{Float64, 3})
        @test_throws "holds decimal numbers, not whole numbers" matread(
            f, one, "inner/values", Matrix{Int64}
        )
        @test_throws "not a MATLAB char array" matread(f, one, "inner/values", String)
        # The error names the path asked for, not the mark it started from.
        @test_throws "\"inner/values\" holds 3 values, not 1" matread(
            f, one, "inner/values", Float64
        )
    end
end

@testitem "the macro reads below a mark too" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        one = matread(f, "runs", Matrix{MatRef})[1, 1]
        v = @matload f, one begin
            count = "count"::Float64
            values = "inner/values"::Matrix{Float64}
            label = "label"::String
        end
        @test v == (count = 4.0, values = [1.0 2.0 3.0], label = "run one")
    end
end

@testitem "a field of a struct array is reached through its marks" setup = [Fixtures] begin
    # struct.mat holds s2, a 1x2 struct array, so its field "a" is an array of marks. This
    # file came from MATLAB itself.
    f = matopen(fixture("struct.mat"))
    items = matread(f, "s2/a", Matrix{MatRef})
    @test size(items) == (1, 2)
    @test matread(f, items[1], Matrix{Float64}) == fill(1.0, 1, 1)
    @test matread(f, items[2], Matrix{Float64}) == fill(2.0, 1, 1)
end

@testitem "a table reads below a mark and through the macro" setup = [Fixtures] begin
    # A named tuple asks for a table. The scalar rule must not claim that type first.
    import MAT

    path = fixture("struct_table_datetime.mat")
    f = matopen(path)
    ref = MAT.matread(path)["s"]["testTable"]
    want = NamedTuple{(:Customer, :FlightNum), Tuple{Vector{String}, Vector{Float64}}}

    s = Mate73.MatRef(Mate73.address(f, "s"))
    t = matread(f, s, "testTable", want)
    @test t.Customer == ref[:Customer]

    v = @matload f, s begin
        table = "testTable"::NamedTuple{
            (:Customer, :FlightNum), Tuple{Vector{String}, Vector{Float64}},
        }
    end
    @test v.table.FlightNum == ref[:FlightNum]
end

@testitem "a scalar reads with the plain type, from a name as well as a mark" setup = [Fixtures] begin
    f = matopen(fixture("simple.mat"))
    @test matread(f, "double", Float64) === 1.0
    @test matread(f, "int32", Int32) === Int32(1)
    g = matopen(fixture("array.mat"))
    @test_throws "holds 4 values, not 1" matread(g, "a2x2", Float64)
end

@testitem "an index in a path names one item of a cell array" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        @test matread(f, "runs/1/count", Float64) === 4.0
        @test matread(f, "runs/2/count", Float64) === 7.0
        @test matread(f, "runs/1/inner/values", Matrix{Float64}) == [1.0 2.0 3.0]
        # An index may stand anywhere a name may, including over a cell inside a struct.
        @test matread(f, "runs/1/parts/name/2", String) == "second"
        @test matread(f, "runs/1/label", String) == "run one"
        # An index reaches the same value a mark does.
        runs = matread(f, "runs", Matrix{MatRef})
        @test matread(f, runs[1, 2], "count", Float64) === matread(f, "runs/2/count", Float64)
        # The untyped read and the key list take the same path.
        @test matread(f, "runs/2/count") == fill(7.0, 1, 1)
        @test sort(matkeys(f, "runs/2")) == ["count", "inner", "label", "parts"]
    end
end

@testitem "an index in a path names one element of a struct array" setup = [Fixtures] begin
    # `s2` is a 1x2 struct array and `s` a single struct, both written by MATLAB.
    f = matopen(fixture("struct.mat"))
    @test matread(f, "s2/1/a", Float64) === 1.0
    @test matread(f, "s2/2/a", Float64) === 2.0
    # MATLAB counts a single struct as a 1x1 struct array, so `s(1)` is `s`.
    @test matread(f, "s/1/b", Matrix{Float64}) == [1.0 2.0]
    @test matread(f, "s/b", Matrix{Float64}) == [1.0 2.0]
    # One element of a struct array is spread across the fields, so it is no object on its own.
    @test_throws "ends at one element of a struct array" matread(f, "s2/1", Float64)
    @test_throws "past the end of a 1x2" matread(f, "s2/3/a", Float64)
    @test_throws "names a single struct, which holds only item 1" matread(f, "s/2/b", Float64)
    # An element of a struct array waits for the field that settles it, so a second index has
    # nothing to apply to.
    @test_throws "two indexes in a row" matread(f, "s2/1/2/a", Float64)
end

@testitem "an index takes one subscript or all of them" setup = [Marks] begin
    mktempdir() do dir
        path = joinpath(dir, "grid.mat")
        # A 2x3 cell, so counting straight through and counting by row and column differ.
        matwrite(path, "c" => reshape(Any[(v = Float64(i),) for i in 1:6], 2, 3))
        f = matopen(path)
        @test matsize(f, "c") == [2, 3]
        @test matread(f, "c/1/v", Float64) === 1.0
        @test matread(f, "c/6/v", Float64) === 6.0
        # MATLAB counts down the columns first, so item 6 is also row 2, column 3.
        @test matread(f, "c/2,3/v", Float64) === 6.0
        @test matread(f, "c/1,1/v", Float64) === 1.0
        @test matread(f, "c/2,1/v", Float64) === 2.0
    end
end

@testitem "a path index that names nothing stops with an error" setup = [Marks] begin
    mktempdir() do dir
        f = matopen(markfile(dir))
        @test_throws "past the end of a 1x2, which holds 2 items" matread(f, "runs/3/count", Float64)
        @test_throws "counts from 1" matread(f, "runs/0/count", Float64)
        @test_throws "give one, or give all 2" matread(f, "runs/1,1,1/count", Float64)
        @test_throws "is outside a 1x2" matread(f, "runs/2,2/count", Float64)
        # A number array is read whole, so there is nothing for an index to name.
        @test_throws "read whole; index the result instead" matread(f, "runs/1/count/1", Float64)
        @test_throws "holds only item 1" matread(f, "runs/1/2", Float64)
        @test_throws "a file holds variables by name" matread(f, "1/count", Float64)
    end
end
