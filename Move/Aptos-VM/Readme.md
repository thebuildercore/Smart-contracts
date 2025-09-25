For hackathon only two contracts are going to be used and is deployed
1. GlobePayXBusiness.move
2. GlobePayXCore.move
   
   *Contracts deployed *
    "transaction_hash": "0x19133542d8236c3415e4e00900fcaf2069a14d6b1006146fd625dd30ffcb0661",
    "gas_used": 6869,
    "gas_unit_price": 100,
    "sender": "5fcbf41aa970222201ccf89ed6d4e3202bd791d5d43f3a4737b901873b2d4573",
--- 
  Check for deployment Transaction submitted: https://explorer.aptoslabs.com/txn/0x19133542d8236c3415e4e00900fcaf2069a14d6b1006146fd625dd30ffcb0661?network=testnet

---
Helper
// frontend/config.ts

export const GLOBEPAYXCORE_ADDRESS = "0x...";

export const GLOBEPAYXBUSINESS_ADDRESS = "0x...";

export const NETWORK_RPC = "https://fullnode.testnet.aptoslabs.com/v1";

---
frontend logic - import abis

import { GLOBEPAYXCORE_ABI } from "./utils/GlobePayXCore_abi";

// example function call

const payload = {

  type: "entry_function_payload",
  
  function: `${GLOBEPAYXCORE_ADDRESS}::GlobePayXCore::some_function`,
  
  arguments: [arg1, arg2],
  
  type_arguments: [],
};
---
