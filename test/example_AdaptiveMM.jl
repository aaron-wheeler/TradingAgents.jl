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
    host_ip_address = "0.0.0.0",
    port = "8080",
    username = "Market Maker",
    password = "liquidity123"
)

ticker = 1
market_open = Dates.now() + Dates.Second(30) # DateTime(2022,7,19,13,19,41,036)
market_close = market_open + Dates.Minute(10)

AdaptiveMM_run(ticker, market_open, market_close, parameters, init_conditions, server_info, collect_data = true)

# include("test/example_AdaptiveMM.jl")