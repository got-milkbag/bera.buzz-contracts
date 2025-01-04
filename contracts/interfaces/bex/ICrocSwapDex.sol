// SPDX-License-Identifier: Unlicensed

pragma solidity >=0.8.4;

interface ICrocSwapDex {
    /* @notice Calls an arbitrary command on one of the sidecar proxy contracts at a specific
     *         index. Not all proxy slots may have a contract attached. If so, this call will
     *         fail.
     *
     * @param callpath The index of the proxy sidecar the command is being called on.
     * @param cmd The arbitrary call data the client is calling the proxy sidecar.
     * @return Arbitrary byte data (if any) returned by the command. */
    function userCmd(
        uint16 callpath,
        bytes calldata cmd
    ) external payable returns (bytes memory);
}
