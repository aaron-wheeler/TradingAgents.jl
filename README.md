# TradingAgents

<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://aaron-wheeler.github.io/TradingAgents.jl/stable/) -->
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://aaron-wheeler.github.io/TradingAgents.jl/dev/)
<!-- [![Build Status](https://github.com/aaron-wheeler/TradingAgents.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/aaron-wheeler/TradingAgents.jl/actions/workflows/CI.yml?query=branch%3Amain) -->

This repository contains the source code for:

* [Introducing a financial simulation ecosystem in Julia | Aaron Wheeler | JuliaCon 2023](https://www.youtube.com/watch?v=C2Itnbwf9hg)
* Preprint (forthcoming)

Related repositories include:

* [Brokerage.jl](https://github.com/aaron-wheeler/Brokerage.jl)

## Description

TradingAgents.jl is a software package that works with [Brokerage.jl](https://github.com/aaron-wheeler/Brokerage.jl) to run agent-based simulations of financial markets. This package implements the core functionality of the simulated agents (i.e., the market participants of the artificial stock market), including trading behaviors for heterogenous agent types and data collection methods for post-simulation analysis. Agents behaviors range from zero-intelligence trading strategies to adaptive trading strategies using online machine learning techniques. 

TradingAgents.jl interfaces with Brokerage.jl, which is implemented as a microservice-based application over REST API. This API enables simulated agents to communicate across various machines, scale to large agent populations, and process decisions in parallel.

## Installation

### Installing Julia
This package uses the [Julia](https://julialang.org) programming language. You can find the installation instructions for Julia [here](https://julialang.org/downloads/).

## Usage
Clone the repository
```sh
git clone https://github.com/aaron-wheeler/TradingAgents.jl.git
```
External package dependencies can be installed from the [Julia REPL](https://docs.julialang.org/en/v1/stdlib/REPL/), press the `]` key to enter [pkg mode](https://pkgdocs.julialang.org/v1/repl/) and the issue the command:
```
add https://github.com/aaron-wheeler/VLLimitOrderBook.jl.git
add https://github.com/aaron-wheeler/Brokerage.jl.git
```

<!-- ## Example

TODO -->