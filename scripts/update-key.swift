// Signs update archives so Fokus only installs updates that came from you.
//   swift scripts/update-key.swift generate     creates the key once, keeps it in the Keychain, prints the public key
//   swift scripts/update-key.swift public       prints the public key again
//   swift scripts/update-key.swift sign <file>  prints the base64 signature of <file>
import CryptoKit
import Foundation

let service = "fokus-update-signing-key"

func run(_ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try! process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}

func storedKey() -> Curve25519.Signing.PrivateKey? {
    let result = run(["find-generic-password", "-a", NSUserName(), "-s", service, "-w"])
    guard result.status == 0, let raw = Data(base64Encoded: result.output) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "generate":
    if storedKey() != nil { fail("Es gibt schon einen Schlüssel. Ein neuer würde Updates für bestehende Installationen unmöglich machen.") }
    let key = Curve25519.Signing.PrivateKey()
    let saved = run(["add-generic-password", "-a", NSUserName(), "-s", service, "-w", key.rawRepresentation.base64EncodedString()])
    guard saved.status == 0 else { fail("Konnte den Schlüssel nicht im Schlüsselbund speichern.") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    guard let key = storedKey() else { fail("Kein Schlüssel im Schlüsselbund. Erst 'generate' ausführen.") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard let path = arguments.dropFirst().first else { fail("Datei fehlt.") }
    guard let key = storedKey() else { fail("Kein Schlüssel im Schlüsselbund.") }
    guard let data = FileManager.default.contents(atPath: path) else { fail("Datei nicht lesbar: \(path)") }
    print(try! key.signature(for: data).base64EncodedString())
default:
    fail("Nutzung: update-key.swift generate | public | sign <datei>")
}
