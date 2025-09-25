export const GLOBEPAYXBUSINESS_ABI = {
  "address": "0x5fcbf41aa970222201ccf89ed6d4e3202bd791d5d43f3a4737b901873b2d4573",
  "name": "GlobePayXBusiness",
  "friends": [],
  "exposed_functions": [
    {
      "name": "batch_pay",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [
        {
          "constraints": []
        }
      ],
      "params": [
        "&signer",
        "vector<address>",
        "vector<u64>",
        "vector<u8>"
      ],
      "return": []
    },
    {
      "name": "create_org",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [],
      "params": [
        "&signer"
      ],
      "return": []
    },
    {
      "name": "fund_treasury",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [
        {
          "constraints": []
        }
      ],
      "params": [
        "&signer",
        "address",
        "vector<u8>",
        "u64"
      ],
      "return": []
    },
    {
      "name": "get_treasury_balance",
      "visibility": "public",
      "is_entry": false,
      "is_view": true,
      "generic_type_params": [
        {
          "constraints": []
        }
      ],
      "params": [
        "address",
        "vector<u8>"
      ],
      "return": [
        "u64"
      ]
    },
    {
      "name": "init_treasury",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [
        {
          "constraints": []
        }
      ],
      "params": [
        "&signer"
      ],
      "return": []
    },
    {
      "name": "internal_transfer",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [
        {
          "constraints": []
        }
      ],
      "params": [
        "&signer",
        "address",
        "vector<u8>",
        "vector<u8>",
        "u64"
      ],
      "return": []
    },
    {
      "name": "is_org_admin",
      "visibility": "public",
      "is_entry": false,
      "is_view": true,
      "generic_type_params": [],
      "params": [
        "address",
        "address"
      ],
      "return": [
        "bool"
      ]
    },
    {
      "name": "withdraw_from_tag",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [
        {
          "constraints": []
        }
      ],
      "params": [
        "&signer",
        "vector<u8>",
        "address",
        "u64"
      ],
      "return": []
    }
  ],
  "structs": [
    {
      "name": "Org",
      "is_native": false,
      "is_event": false,
      "abilities": [
        "key"
      ],
      "generic_type_params": [],
      "fields": [
        {
          "name": "admin",
          "type": "address"
        }
      ]
    },
    {
      "name": "OrgTreasury",
      "is_native": false,
      "is_event": false,
      "abilities": [
        "key"
      ],
      "generic_type_params": [
        {
          "constraints": []
        }
      ],
      "fields": [
        {
          "name": "org",
          "type": "address"
        },
        {
          "name": "balances",
          "type": "0x1::table::Table<vector<u8>, u64>"
        }
      ]
    },
    {
      "name": "PayrollEvent",
      "is_native": false,
      "is_event": true,
      "abilities": [
        "drop",
        "store"
      ],
      "generic_type_params": [],
      "fields": [
        {
          "name": "employer",
          "type": "address"
        },
        {
          "name": "employee",
          "type": "address"
        },
        {
          "name": "coin_type",
          "type": "vector<u8>"
        },
        {
          "name": "amount",
          "type": "u64"
        },
        {
          "name": "memo",
          "type": "vector<u8>"
        },
        {
          "name": "ts",
          "type": "u64"
        }
      ]
    },
    {
      "name": "TreasuryEvent",
      "is_native": false,
      "is_event": true,
      "abilities": [
        "drop",
        "store"
      ],
      "generic_type_params": [],
      "fields": [
        {
          "name": "org",
          "type": "address"
        },
        {
          "name": "from_tag",
          "type": "vector<u8>"
        },
        {
          "name": "to_tag",
          "type": "vector<u8>"
        },
        {
          "name": "coin_type",
          "type": "vector<u8>"
        },
        {
          "name": "amount",
          "type": "u64"
        },
        {
          "name": "ts",
          "type": "u64"
        }
      ]
    }
  ]
} as const;
