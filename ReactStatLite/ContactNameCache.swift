import Foundation
import Contacts

final class ContactNameCache {
    static let shared = ContactNameCache()

    private let store = CNContactStore()
    private let lock = NSLock()
    private var warmed = false
    private var warming = false

    // normalized phone/email -> display name
    private var map: [String: String] = [:]

    private init() {}

    // MARK: - Authorization helpers

    var contactsAuthStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    var isAuthorized: Bool {
        contactsAuthStatus == .authorized
    }

    var canRequestContacts: Bool {
        contactsAuthStatus == .notDetermined
    }

    /// If true, user denied/restricted -> you must send them to Settings.
    var needsSettingsForContacts: Bool {
        contactsAuthStatus == .denied || contactsAuthStatus == .restricted
    }

    // MARK: - Warm cache

    /// Safe to call often. It will do real work only once (and only if authorized).
    func warmIfNeeded() {
        lock.lock()
        if warmed || warming {
            lock.unlock()
            return
        }

        guard isAuthorized else {
            map = [:]
            lock.unlock()
            return
        }

        warming = true
        lock.unlock()

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true

        var newMap: [String: String] = [:]

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let name = Self.displayName(for: contact)
                guard name != "Unknown" else { return }

                for e in contact.emailAddresses {
                    let s = (e.value as String)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    if !s.isEmpty { newMap[s] = name }
                }

                for p in contact.phoneNumbers {
                    let raw = p.value.stringValue
                    let digits = raw.filter { $0.isNumber }
                    guard !digits.isEmpty else { continue }

                    newMap[digits] = name
                    // common US variants
                    if digits.count == 10 { newMap["1" + digits] = name }
                    if digits.count == 11, digits.hasPrefix("1") { newMap[String(digits.dropFirst())] = name }
                }
            }
        } catch {
            newMap = [:]
        }

        lock.lock()
        map = newMap
        warmed = true
        warming = false
        lock.unlock()
    }

    /// If authorization changes while app is running, call this to re-warm with new permissions.
    func resetWarmState() {
        lock.lock()
        warmed = false
        warming = false
        map = [:]
        lock.unlock()
    }

    /// Converts a Messages DB handle.id (phone/email) into a display name if possible.
    func resolve(_ raw: String) -> String {
        warmIfNeeded()

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }

        if trimmed == "Me" { return "Me" }

        if trimmed.contains("@") {
            let k = trimmed.lowercased()
            return map[k] ?? trimmed
        }

        let digits = trimmed.filter { $0.isNumber }
        if digits.isEmpty { return trimmed }

        if let v = map[digits] { return v }
        if digits.count == 10, let v = map["1" + digits] { return v }
        if digits.count == 11, digits.hasPrefix("1"), let v = map[String(digits.dropFirst())] { return v }

        return trimmed
    }

    private static func displayName(for c: CNContact) -> String {
        let full = [c.givenName, c.familyName]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }

        let org = c.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !org.isEmpty { return org }

        return "Unknown"
    }
}
