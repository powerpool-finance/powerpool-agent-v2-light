# PowerPool Agent V2 Light

WARNING: The previous version of PowerPool Agent V2 v2.2.0, now referred to as `light`, has been temporarily deprecated in favor of the `randao` version. We plan to reintroduce support for it in the future. You can find `randao` version here https://github.com/powerpool-finance/powerpool-agent-v2.

## How to run tests

* Clone the repo `git clone  --recurse-submodules https://github.com/powerpool-finance/powerpool-agent-v2.git`
* Set up foundry https://github.com/foundry-rs/foundry#installation. At the moment the following instructions are valid:
  * `curl -L https://foundry.paradigm.xyz | bash`
  * Reload your PATH env var, for ex. by restarting a terminal session
  * `foundryup`
* Run all the tests:
```shell
forge test -vvv
```
* Run a particular test (verbose details only if a test fails, 3-v):
```shell
forge test -vvv -m testSetAgentParams
```
* Print verbose debug info for a test (4-v):
```shell
forge test -vvvv -m testSetAgentParams
```
* Re-compile all contracts with sizes output:
```shell
forge build --sizes --force
```
