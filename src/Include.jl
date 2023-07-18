# setup internal paths -
_PATH_TO_SRC = dirname(pathof(@__MODULE__))

# load external packages that we depend upon -
using Brokerage
using Distributions
using Distributed
using Dates
using Random
using CSV
using DataFrames
using Convex
using ECOS
using LinearAlgebra
using JuMP
import Ipopt

# load my codes -
include(joinpath(_PATH_TO_SRC, "TraderUtils.jl"))
include(joinpath(_PATH_TO_SRC, "FundamentalTraders.jl"))
include(joinpath(_PATH_TO_SRC, "ZeroTrader.jl"))
include(joinpath(_PATH_TO_SRC, "ParallelLiquidityTaker.jl"))
include(joinpath(_PATH_TO_SRC, "ParallelLiquidityProvider.jl"))
include(joinpath(_PATH_TO_SRC, "RandomMarketMaker.jl"))
include(joinpath(_PATH_TO_SRC, "ParallelMarketMaker.jl"))
include(joinpath(_PATH_TO_SRC, "AdaptiveMarketMaker.jl"))