#!/usr/bin/swift
import Foundation
import CryptoKit

// Verification is rooted in the public key committed with this fork. This tool never reads secrets.
do {
    guard CommandLine.arguments.count == 4 else {
        throw NSError(domain: "ReleaseSignature", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "usage: verify_archive_signature.swift PUBLIC_KEY_FILE ARCHIVE SIGNATURE"])
    }
    let encoded = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let publicData = Data(base64Encoded: encoded), publicData.count == 32,
          let signature = Data(base64Encoded: CommandLine.arguments[3]), signature.count == 64 else {
        throw NSError(domain: "ReleaseSignature", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Invalid public key or signature encoding"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "ReleaseSignature", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Archive signature does not match this fork's public key"])
    }
    print("Archive signature verified against the committed public key")
} catch {
    FileHandle.standardError.write(Data("Release verification failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
