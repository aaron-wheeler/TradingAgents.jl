"""
Example script for running the PLP algorithm.
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

# Example configuration
num_traders, num_assets = 5850, 5

parameters = (
    init_cash_range = (5000.0 * num_assets):0.01:(15000.0 * num_assets),
    init_shares_range = 50:1:150,
    trade_freq = 720, # avg seconds between trades
    num_ids = 320 + 650 # number of reserved ids set aside for other agents (e.g., liquidity takers and market makers)
)

server_info = (
    host_ip_address = "0.0.0.0",
    port = "8080",
    username = "Liquidity Provider",
    password = "provide123"
)

PLP_run(num_traders, num_assets, parameters, server_info, print_msg=true)

# include("test/example_PLP.jl")