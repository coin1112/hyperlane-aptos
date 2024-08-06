/**
 * This file was automatically generated by @cosmwasm/ts-codegen@0.35.3.
 * DO NOT MODIFY IT BY HAND. Instead, modify the source JSONSchema file,
 * and run the @cosmwasm/ts-codegen generate command to regenerate this file.
 */

export interface InstantiateMsg {
  isms: string[];
  owner: string;
  threshold: number;
}
export type ExecuteMsg =
  | {
      ownable: OwnableMsg;
    }
  | {
      set_isms: {
        isms: string[];
      };
    };
export type OwnableMsg =
  | {
      init_ownership_transfer: {
        next_owner: string;
      };
    }
  | {
      revoke_ownership_transfer: {};
    }
  | {
      claim_ownership: {};
    };
export type QueryMsg =
  | {
      ownable: OwnableQueryMsg;
    }
  | {
      ism: IsmQueryMsg;
    }
  | {
      aggregate_ism: AggregateIsmQueryMsg;
    };
export type OwnableQueryMsg =
  | {
      get_owner: {};
    }
  | {
      get_pending_owner: {};
    };
export type IsmQueryMsg =
  | {
      module_type: {};
    }
  | {
      verify: {
        message: HexBinary;
        metadata: HexBinary;
      };
    }
  | {
      verify_info: {
        message: HexBinary;
      };
    };
export type HexBinary = string;
export type AggregateIsmQueryMsg = {
  isms: {};
};
export type Addr = string;
export interface OwnerResponse {
  owner: Addr;
}
export interface PendingOwnerResponse {
  pending_owner?: Addr | null;
}
export interface IsmsResponse {
  isms: string[];
}
export type IsmType =
  | 'unused'
  | 'routing'
  | 'aggregation'
  | 'legacy_multisig'
  | 'merkle_root_multisig'
  | 'message_id_multisig'
  | 'null'
  | 'ccip_read';
export interface ModuleTypeResponse {
  type: IsmType;
}
export interface VerifyResponse {
  verified: boolean;
}
export interface VerifyInfoResponse {
  threshold: number;
  validators: HexBinary[];
}
