using Documenter
using DocumenterVitepress
using Mate73

makedocs(;
    modules = [Mate73],
    authors = "el-oso",
    sitename = "Mate73.jl",
    format = DocumenterVitepress.MarkdownVitepress(;
        repo = "github.com/el-oso/Mate73.jl",
        devbranch = "master",
        devurl = "dev",
    ),
    pages = [
        "Home" => "index.md",
        "The format" => "format.md",
        "Trimmed binaries" => "trim.md",
        "API" => "api.md",
    ],
    warnonly = [:missing_docs],
)

# Documenter's own deploydocs leaves a Vitepress build in the wrong place and the site 404s.
DocumenterVitepress.deploydocs(;
    repo = "github.com/el-oso/Mate73.jl",
    target = joinpath(@__DIR__, "build"),
    branch = "gh-pages",
    devbranch = "master",
    push_preview = true,
)
