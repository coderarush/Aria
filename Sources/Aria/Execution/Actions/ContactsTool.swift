import Foundation
import Contacts

/// "What's Sam's email?" / "when is Mom's birthday?" — reads the user's real
/// macOS Contacts (permission-gated; asks once, degrades gracefully). Pairs
/// with the on-device EntityStore: Contacts holds the address book, the
/// EntityStore holds who the user *talks about* — together "email Sara" both
/// resolves and addresses.
struct ContactsTool: AriaTool {
    static let name = "contacts_search"
    static let description = "Search the user's macOS Contacts by name. Returns matching people with phone numbers, email addresses, and birthday when set. Input: {name: full or partial name}. Use to resolve 'email Sam' / 'call Alex' / birthday questions."
    static let paramHints: [String: String] = [
        "name": "Full or partial contact name, e.g. 'Sam' or 'Sam Rivera'"
    ]

    func run(input: [String: String]) async throws -> ToolResult {
        guard let name = input["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return .fail("Missing input: name — whose contact card should I look up?")
        }

        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            break
        case .notDetermined:
            let granted = (try? await store.requestAccess(for: .contacts)) ?? false
            guard granted else {
                return .fail("Contacts access was declined — enable it in System Settings → Privacy & Security → Contacts if you want me to look people up.")
            }
        default:
            return .fail("I don't have Contacts access — enable it in System Settings → Privacy & Security → Contacts.")
        }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactBirthdayKey,
            CNContactOrganizationNameKey,
        ].map { $0 as CNKeyDescriptor }

        let predicate = CNContact.predicateForContacts(matchingName: name)
        let matches: [CNContact]
        do {
            matches = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
        } catch {
            return .fail("Couldn't search Contacts right now.", diagnostics: "\(error)")
        }
        guard !matches.isEmpty else {
            return .ok("No contact matching “\(name)”.")
        }

        let cards = matches.prefix(5).map(Self.card)
        return .ok(cards.joined(separator: "\n\n"))
    }

    /// Pure formatter (testable with an in-memory CNMutableContact).
    static func card(for contact: CNContact) -> String {
        var lines: [String] = []
        var title = [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }.joined(separator: " ")
        if title.isEmpty { title = contact.nickname }
        if !contact.organizationName.isEmpty { title += " (\(contact.organizationName))" }
        lines.append(title)

        for phone in contact.phoneNumbers {
            let kind = phone.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "phone"
            lines.append("  \(kind): \(phone.value.stringValue)")
        }
        for email in contact.emailAddresses {
            let kind = email.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "email"
            lines.append("  \(kind): \(email.value)")
        }
        if let birthday = contact.birthday, let month = birthday.month, let day = birthday.day {
            let months = ["", "January", "February", "March", "April", "May", "June", "July",
                          "August", "September", "October", "November", "December"]
            var line = "  birthday: \(months[month]) \(day)"
            if let year = birthday.year { line += ", \(year)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
