"""
Configuration file for running a single test of the PLP algorithm.
"""

using Distributed
addprocs(4) # add workers

# Set up package environment on workers
@everywhere begin
    using Pkg
    Pkg.activate(".")
end

# Load packages on workers
@everywhere begin
    using TradingAgents, Dates, Brokerage, Distributions
end

# Example use case
parameters = (
    init_cash_range = 10000.0:0.01:30000.0,
    init_shares_range = 0:1:120,
    trade_freq = 13, # 7200, # avg seconds between trades; based on Paddrik et al. (2012) and Paulin et al. (2019)
    num_ids = 30 # + 70 # number of reserved ids set aside for other agents
)

server_info = (
    # host_ip_address = "0.0.0.0",
    host_ip_address = "128.253.116.77",
    port = "8080",
    username = "Liquidity Provider",
    password = "provide123"
)

num_traders, num_assets = 10, 1 # 6500, 1 # based on Paddrik et al. (2012) and Paulin et al. (2019)

PLP_run(num_traders, num_assets, parameters, server_info, print_msg=true)

# include("test/example_PLP.jl")