using TradingAgents
using Documenter

DocMeta.setdocmeta!(TradingAgents, :DocTestSetup, :(using TradingAgents); recursive=true)

makedocs(;
    modules=[TradingAgents],
    authors="aaron-wheeler",
    repo="https://github.com/aaron-wheeler/TradingAgents.jl/blob/{commit}{path}#{line}",
    sitename="TradingAgents.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://aaron-wheeler.github.io/TradingAgents.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/aaron-wheeler/TradingAgents.jl",
    devbranch="main",
)
