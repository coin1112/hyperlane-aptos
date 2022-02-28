// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.9;

import "../governance/GovernanceRouter.sol";
import {TypeCasts} from "../XAppConnectionManager.sol";

contract TestGovernanceRouter is GovernanceRouter {
    constructor(uint32 _localDomain, uint256 _recoveryTimelock)
        GovernanceRouter(_localDomain, 50)
    {} // solhint-disable-line no-empty-blocks

    function testSetRouter(uint32 _domain, bytes32 _router) external {
        _setRouter(_domain, _router); // set the router locally

        bytes memory _setRouterMessage = GovernanceMessage.formatSetRouter(
            _domain,
            _router
        );

        _sendToAllRemoteRouters(_setRouterMessage);
    }

    function containsDomain(uint32 _domain) external view returns (bool) {
        for (uint256 i = 0; i < domains.length; i++) {
            if (domains[i] == _domain) return true;
        }

        return false;
    }
}
