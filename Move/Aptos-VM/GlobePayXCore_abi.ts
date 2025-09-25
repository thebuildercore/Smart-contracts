export const GLOBEPAYXCORE_ABI = {
  "address": "0x5fcbf41aa970222201ccf89ed6d4e3202bd791d5d43f3a4737b901873b2d4573",
  "name": "GlobePayXCore",
  "friends": [],
  "exposed_functions": [
    {
      "name": "is_owner",
      "visibility": "public",
      "is_entry": false,
      "is_view": true,
      "generic_type_params": [],
      "params": [
        "address"
      ],
      "return": [
        "bool"
      ]
    },
    {
      "name": "emit_generic_audit",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [],
      "params": [
        "&signer",
        "vector<u8>",
        "vector<u8>"
      ],
      "return": []
    },
    {
      "name": "execute_swap",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [
        {
          "constraints": []
        },
        {
          "constraints": []
        }
      ],
      "params": [
        "&signer",
        "u64"
      ],
      "return": []
    },
    {
      "name": "get_swap_counter",
      "visibility": "public",
      "is_entry": false,
      "is_view": true,
      "generic_type_params": [],
      "params": [],
      "return": [
        "u64"
      ]
    },
    {
      "name": "get_swap_fee_bps",
      "visibility": "public",
      "is_entry": false,
      "is_view": true,
      "generic_type_params": [],
      "params": [],
      "return": [
        "u64"
      ]
    },
    {
      "name": "get_swap_info",
      "visibility": "public",
      "is_entry": false,
      "is_view": true,
      "generic_type_params": [],
      "params": [
        "u64"
      ],
      "return": [
        "address",
        "u64",
        "u64",
        "u128",
        "u64",
        "bool"
      ]
    },
    {
      "name": "send_stablecoin",
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
        "u64"
      ],
      "return": []
    },
    {
      "name": "set_swap_fee_bps",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [],
      "params": [
        "&signer",
        "u64"
      ],
      "return": []
    },
    {
      "name": "swap_request",
      "visibility": "public",
      "is_entry": true,
      "is_view": false,
      "generic_type_params": [
        {
          "constraints": []
        },
        {
          "constraints": []
        }
      ],
      "params": [
        "&signer",
        "u64",
        "u64",
        "u128"
      ],
      "return": []
    }
  ],
  "structs": [
    {
      "name": "TransferEvent",
      "is_native": false,
      "is_event": true,
      "abilities": [
        "drop",
        "store"
      ],
      "generic_type_params": [],
      "fields": [
        {
          "name": "sender",
          "type": "address"
        },
        {
          "name": "recipient",
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
          "name": "ts",
          "type": "u64"
        }
      ]
    },
    {
      "name": "AuditEvent",
      "is_native": false,
      "is_event": true,
      "abilities": [
        "drop",
        "store"
      ],
      "generic_type_params": [],
      "fields": [
        {
          "name": "caller",
          "type": "address"
        },
        {
          "name": "action",
          "type": "vector<u8>"
        },
        {
          "name": "data",
          "type": "vector<u8>"
        },
        {
          "name": "ts",
          "type": "u64"
        }
      ]
    },
    {
      "name": "CoreAdmin",
      "is_native": false,
      "is_event": false,
      "abilities": [
        "key"
      ],
      "generic_type_params": [],
      "fields": [
        {
          "name": "owner",
          "type": "address"
        },
        {
          "name": "swap_fee_bps",
          "type": "u64"
        },
        {
          "name": "swap_counter",
          "type": "u64"
        }
      ]
    },
    {
      "name": "SwapEvent",
      "is_native": false,
      "is_event": true,
      "abilities": [
        "drop",
        "store"
      ],
      "generic_type_params": [],
      "fields": [
        {
          "name": "user",
          "type": "address"
        },
        {
          "name": "coin_in",
          "type": "vector<u8>"
        },
        {
          "name": "coin_out",
          "type": "vector<u8>"
        },
        {
          "name": "amount_in",
          "type": "u64"
        },
        {
          "name": "amount_out",
          "type": "u64"
        },
        {
          "name": "rate_1e18",
          "type": "u128"
        },
        {
          "name": "fee",
          "type": "u64"
        },
        {
          "name": "ts",
          "type": "u64"
        }
      ]
    },
    {
      "name": "SwapInfo",
      "is_native": false,
      "is_event": false,
      "abilities": [
        "drop",
        "store"
      ],
      "generic_type_params": [],
      "fields": [
        {
          "name": "id",
          "type": "u64"
        },
        {
          "name": "user",
          "type": "address"
        },
        {
          "name": "coin_in_name",
          "type": "vector<u8>"
        },
        {
          "name": "coin_out_name",
          "type": "vector<u8>"
        },
        {
          "name": "amount_in",
          "type": "u64"
        },
        {
          "name": "amount_out",
          "type": "u64"
        },
        {
          "name": "rate_1e18",
          "type": "u128"
        },
        {
          "name": "fee",
          "type": "u64"
        },
        {
          "name": "executed",
          "type": "bool"
        },
        {
          "name": "ts",
          "type": "u64"
        }
      ]
    },
    {
      "name": "SwapRequests",
      "is_native": false,
      "is_event": false,
      "abilities": [
        "key"
      ],
      "generic_type_params": [],
      "fields": [
        {
          "name": "requests",
          "type": "0x1::table::Table<u64, 0x5fcbf41aa970222201ccf89ed6d4e3202bd791d5d43f3a4737b901873b2d4573::GlobePayXCore::SwapInfo>"
        }
      ]
    }
  ]
} as const;
