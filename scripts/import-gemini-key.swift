import Foundation
import Security
guard CommandLine.arguments.count == 2 else { fatalError("Usage: swift scripts/import-gemini-key.swift /path/to/.env") }
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
guard let line = source.split(separator: "\n").first(where: { $0.hasPrefix("GEMINI_API_KEY=") }) else { fatalError("GEMINI_API_KEY missing") }
let key = line.dropFirst("GEMINI_API_KEY=".count).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.computa.gemini", kSecAttrAccount as String: "api-key"]
let value = [kSecValueData as String: Data(key.utf8)]
let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
if status == errSecItemNotFound {
 var entry = query; entry.merge(value) { _, new in new }
 let added = SecItemAdd(entry as CFDictionary, nil)
 guard added == errSecSuccess else { fatalError("Keychain import failed: \(added)") }
} else if status != errSecSuccess { fatalError("Keychain update failed: \(status)") }
print("Gemini key imported into Keychain; value not printed.")
