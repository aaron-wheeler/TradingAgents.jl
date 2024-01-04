# TradingAgents.jl

<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://aaron-wheeler.github.io/TradingAgents.jl/stable/) -->
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://aaron-wheeler.github.io/TradingAgents.jl/dev/)
<!-- [![Build Status](https://github.com/aaron-wheeler/TradingAgents.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/aaron-wheeler/TradingAgents.jl/actions/workflows/CI.yml?query=branch%3Amain) -->

This repository contains the source code for:

* [Introducing a financial simulation ecosystem in Julia | Aaron Wheeler | JuliaCon 2023](https://www.youtube.com/watch?v=C2Itnbwf9hg)
* [arXiv preprint] [Scalable Agent-Based Modeling for Complex Financial Market Simulations](https://arxiv.org/abs/2312.14903)

Related repositories include:

* [Brokerage.jl](https://github.com/aaron-wheeler/Brokerage.jl)
* [VLLimitOrderBook.jl](https://github.com/aaron-wheeler/VLLimitOrderBook.jl)

## Description

TradingAgents.jl is a software package that works with [Brokerage.jl](https://github.com/aaron-wheeler/Brokerage.jl) to run agent-based simulations of financial markets. This package implements the core functionality of the simulated agents (i.e., the market participants of the artificial stock market), including trading behaviors for heterogenous agent types and data collection methods for post-simulation analysis. Agent behaviors range from zero-intelligence trading strategies to adaptive trading strategies using online machine learning techniques. 

TradingAgents.jl interfaces with Brokerage.jl, which is implemented as a microservice-based application over REST API. This API enables simulated agents to communicate across various machines, scale to large agent populations, and process decisions in parallel.

## Usage

### Installing Julia
This package uses the [Julia](https://julialang.org) programming language. You can find the installation instructions for Julia [here](https://julialang.org/downloads/).

### Installing TradingAgents.jl
Clone the repository
```zsh
git clone https://github.com/aaron-wheeler/TradingAgents.jl.git
```
External package dependencies (such as the matching engine package [VLLimitOrderBook.jl](https://github.com/aaron-wheeler/VLLimitOrderBook.jl) and trading platform [Brokerage.jl](https://github.com/aaron-wheeler/Brokerage.jl)) can be installed from the [Julia REPL](https://docs.julialang.org/en/v1/stdlib/REPL/); from the REPL, press the `]` key to enter [pkg mode](https://pkgdocs.julialang.org/v1/repl/) and then issue the commands:
```
add https://github.com/aaron-wheeler/VLLimitOrderBook.jl.git
add https://github.com/aaron-wheeler/Brokerage.jl.git
```

### Example - Multi-asset Simulation Trial
An example of a medium-scale multi-asset simulation trial is provided below. To start, initialize the Brokerage server from the host machine using the Brokerage.jl package:
```julia
using Brokerage, Dates, Sockets

# initialize database and LOB(s)
const DBFILE = joinpath(dirname(pathof(Brokerage)), "../test/portfolio.sqlite")
const AUTHFILE = "file://" * joinpath(dirname(pathof(Brokerage)), "../resources/authkeys.json")
Mapper.MM_COUNTER[] = 200 # number of accounts reserved for market makers
init_price = rand(85.0:115.0, 5) # specify initial price of 5 unique assets to be between $85 - $115
OMS.NUM_ASSETS[] = length(init_price) # number of assets
OMS.PRICE_BUFFER_CAPACITY[] = 100 # number of price points to store
OMS.MARKET_OPEN_T[] = Dates.now() + Dates.Hour(2) # market open time, delayed by time needed to initialize all agent portfolios (varies by machine)
OMS.MARKET_CLOSE_T[] = OMS.MARKET_OPEN_T[] + Dates.Hour(1) # market close time
OMS.init_LOB!(OMS.ob, init_price, OMS.LP_order_vol, OMS.LP_cancel_vol, OMS.trade_volume_t, OMS.price_buffer)

# initialize server
server = @async Brokerage.remote_run(DBFILE, AUTHFILE)
    
# show message to user
port_number = 8080
host_ip_address = Sockets.getipaddr()
@info "Server started. address: $(host_ip_address) port: $(port_number) at $(Dates.now(Dates.UTC))"
```
The `host_ip_address` and `port_number` are used to connect to the Brokerage server from either the same or a different machine. Once the Brokerage server is initialized, agents register with the Brokerage and then trading can begin. To generate market activity, we'll use the agent behaviors defined in TradingAgents.jl; specifically, we'll use the Liquidity Takers, Liquidity Providers, and Market Maker agent types.

Each of these agent types will be run on its own process (either through a new terminal instance or on a new machine entirely, etc.) and will begin trading once the market opens (defined on the Brokerage server). In this example, we'll make use of parallel agent types, which necessitakes the use of the [Distributed.jl](https://github.com/JuliaLang/Distributed.jl) package. For simplicity, we'll use a single worker for each parallel agent type. Each of the following scripts should be ran simultaneously.

The following code snippet is an example script for running the parallel liquidity taker algorithm. Note the `num_MM` variable, which must match the number of market makers present in the simulation. 
```julia
using Distributed
addprocs(1) # add workers

# Set up package environment on workers
@everywhere begin
    using Pkg
    Pkg.activate(".")
end

# Load packages on workers
@everywhere begin
    using TradingAgents, Dates, Brokerage, Distributions
end

# Example configuration
num_traders, num_assets = 650, 5

parameters = (
    username = "Liquidity Taker",
    password = "password123",
    init_cash_range = (5000.0 * num_assets):0.01:(15000.0 * num_assets),
    init_shares_range = 50:1:150,
    trade_freq = 720, # avg seconds between trades
    num_MM = 200 # number of reserved ids set aside for non-brokerage users (e.g., market makers)
)

server_info = (
    host_ip_address = "0.0.0.0", # FILL ME IN
    port = "8080" # FILL ME IN
)

# run the parallel liquidity taker algorithm
PLT_run(num_traders, num_assets, parameters, server_info, print_msg=true)
```

The following code snippet is an example script for running the parallel liquidity provider algorithm. Note the `num_ids` variable, which must match the number of market makers and liquidity takers present in the simulation. 
```julia
using Distributed
addprocs(1) # add workers

# Set up package environment on workers
@everywhere begin
    using Pkg
    Pkg.activate(".")
end

# Load packages on workers
@everywhere begin
    using TradingAgents, Dates, Brokerage, Distributions
end

# Example configuration
num_traders, num_assets = 5850, 5

parameters = (
    init_cash_range = (5000.0 * num_assets):0.01:(15000.0 * num_assets),
    init_shares_range = 50:1:150,
    trade_freq = 720, # avg seconds between trades
    num_ids = 200 + 650 # number of reserved ids set aside for other agents (e.g., liquidity takers and market makers)
)

server_info = (
    host_ip_address = "0.0.0.0", # FILL ME IN
    port = "8080", # FILL ME IN
    username = "Liquidity Provider",
    password = "provide123"
)

# run the parallel liquidity provider algorithm
PLP_run(num_traders, num_assets, parameters, server_info, print_msg=true)
```
The following code snippet is an example script for running the parallel market maker algorithm: 
```julia
using TradingAgents, Dates

# Example configuration
num_agents, num_assets = 200, 5

parameters = (
    ϵ_min = -0.5, # lower bound for price deviation variable
    ϵ_max = 1.0, # upper bound for price deviation variable
    unit_trade_size = 100, # amount of shares behind each quote
    trade_freq = 2 # avg seconds between trades 
)

server_info = (
    host_ip_address = "0.0.0.0", # FILL ME IN
    port = "8080", # FILL ME IN
    username = "Parallel Market Maker", 
    password = "liquidity000"
)

# run the parallel market maker algorithm
PMM_run(num_agents, num_assets, parameters, server_info, collect_data = true, print_msg = true)
```

[Optional] The following code snippet is an example script for running the intelligent agent/adaptive market maker algorithm. This agent type is computationally intensive and can only trade a single asset. Currently, this package does not support running the intelligent agent type at the same time as the parallel market makers. To use this agent type with other market makers, please refer to the [RandomMarketMaker](https://github.com/aaron-wheeler/TradingAgents.jl/blob/main/src/RandomMarketMaker.jl) agent type (if the RandomMM agent type is used, make sure that the registered ID is unique from the intelligent agent). 
```julia
using TradingAgents, Dates

## Example use case
parameters = (
    η_ms = 0.25, # market share target
    γ = 2, # risk aversion
    δ_tol = 0.05, # optimization tolerance
    inventory_limit = 3000, # maximum and minimum number of share holdings allowed
    unit_trade_size = 15, # amount of shares behind each quote
    trade_freq = 2 # seconds between each trading invocation
)

init_conditions = (
    cash = 0, # initial cash balance
    z = 0, # initial inventory
    num_init_quotes = 10, # number of random quotes to send out per initialization round
    num_init_rounds = 5 # number of initialization rounds
)

server_info = (
    host_ip_address = "0.0.0.0", # FILL ME IN
    port = "8080", # FILL ME IN
    username = "Market Maker",
    password = "liquidity123"
)

ticker = 1 # ticker ID of the asset to trade

# run the adaptive market maker algorithm
AdaptiveMM_run(ticker, parameters, init_conditions, server_info, collect_data = true)
```
Note: as the agent population grows, more time will need to be allocated toward delaying the market open time. For example, a total agent population of 1,000 may need 3 minutes to set up and a total agent population of 100,000 may need 2 hours (therefore, to run a large-scale simulation, define the appropiate `OMS.MARKET_OPEN_T[] = Dates.now() + Delay Time` in the Brokerage server initialization and run each agent script). The exact delay time needed will vary based on the type of hardware used.

For ease of use, each example agent script can be found in the [test](https://github.com/aaron-wheeler/TradingAgents.jl/tree/main/test) folder and can be modified and then called using an include statement from the REPL (i.e., enter the Julia REPL and run `include("test/example_PLT.jl")`)