# Tellor Contracts

See https://github.com/evilrobot-01/tellor for overview.

- Why is removeParachainValue function in spec for controller contracts? Doesn’t this already happen on oracle consumer chain?

### todo
    - Parachain.sol – Does removeValue ever need to go crossChain?  (I think its all on consumerchain)

    - Parachain.sol – why do you have that “parachain” function?  Just encode it like that where you call it to save gas.  Same with all the other “encode” functions.  Much cheaper gas wise to not have separate one-off functions you only call once 

    - Staking.sol – you never use the owner variable.  Or the error or the modifier ParachainStaking – do you ever remove the values when a dispute happens?
- 
