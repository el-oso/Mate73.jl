# Writes the types MAT.jl reads that are not plain dictionaries or arrays. Its class objects,
# opaque objects and function handles are already `AbstractDict`s, so they need nothing here.
module Mate73MATExt

using Mate73: Mate73, MatWriter
using MAT: MatlabStructArray, MatlabTable

# ponytail: written as a cell array of structs, not a MATLAB struct array, which this
# package's writer does not produce. MATLAB reads it back as a cell of structs.
Mate73.addvalue!(w::MatWriter, parent::Int, name::String, s::MatlabStructArray) =
    Mate73.addvalue!(w, parent, name, Array(s))

# ponytail: a struct of columns, since nothing in this package writes a MATLAB table.
Mate73.addvalue!(w::MatWriter, parent::Int, name::String, t::MatlabTable) =
    Mate73.addvalue!(w, parent, name, Dict{String, Any}(String.(t.names) .=> t.columns))

end # module Mate73MATExt
