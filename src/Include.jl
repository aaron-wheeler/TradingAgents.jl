# setup internal paths -
_PATH_TO_SRC = dirname(pathof(@__MODULE__))

# load external packages that we depend upon -
using Brokerage
using Distributions
using Dates
using Random

# load my codes -
include(joinpath(_PATH_TO_SRC, "TraderUtils.jl"))
include(joinpath(_PATH_TO_SRC, "FundamentalTraders.jl"))