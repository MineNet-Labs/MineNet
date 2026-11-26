// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

/**
 * @title ICertificateRegistry
 * @author 0xEmmyb2
 * @notice What other MineNet contracts need from {CertificateRegistry}: whether a lot holds valid certificates.
 */
interface ICertificateRegistry {
    /**
     * @notice Whether a certificate exists, is not revoked and has not expired.
     * @param certId Certificate id.
     * @return True if valid.
     */
    function isValid(uint256 certId) external view returns (bool);

    /**
     * @notice Whether a lot's current certificate of `certType` is valid.
     * @param tokenId Lot.
     * @param certType Certificate type.
     * @return True if unrevoked and unexpired.
     */
    function hasValidCertificate(uint256 tokenId, bytes32 certType) external view returns (bool);

    /**
     * @notice Whether a lot holds a valid current certificate of every listed type.
     * @param tokenId Lot.
     * @param certTypes Certificate types.
     * @return True if every type is covered (also true for an empty list).
     */
    function hasValidCertificates(uint256 tokenId, bytes32[] memory certTypes) external view returns (bool);
}
