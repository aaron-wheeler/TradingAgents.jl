"""
Example script for running the PMM algorithm.
"""

using TradingAgents, Dates

# Example configuration
num_agents, num_assets = 320, 5

parameters = (
    ϵ_min = -0.5, # lower bound for price deviation variable
    ϵ_max = 1.0, # upper bound for price deviation variable
    unit_trade_size = 100, # amount of shares behind each quote
    trade_freq = 2 # avg seconds between trades 
)

server_info = (
    host_ip_address = "0.0.0.0",
    port = "8080",
    username = "Parallel Market Maker",
    password = "liquidity000"
)

PMM_run(num_agents, num_assets, parameters, server_info, collect_data = true, print_msg = true)

# include("test/example_PMM.jl")