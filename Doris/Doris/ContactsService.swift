//
//  ContactsService.swift
//  Doris
//
//  Created by Adam Bell on 12/31/25.
//

import Foundation
import Contacts

class ContactsService {
    private let store = CNContactStore()
    private var hasAccess = false
    
    init() {
        print("👤 Contacts: Initialized")
    }
    
    // MARK: - Authorization
    
    func requestAccess() async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        
        switch status {
        case .authorized:
            hasAccess = true
            print("🟢 Contacts: Already authorized")
            return
            
        case .notDetermined:
            hasAccess = try await store.requestAccess(for: .contacts)
            if hasAccess {
                print("🟢 Contacts: Access granted")
            } else {
                print("🔴 Contacts: Access denied by user")
                throw ContactsError.accessDenied
            }
            
        case .denied, .restricted:
            print("🔴 Contacts: Access denied or restricted")
            throw ContactsError.accessDenied
            
        case .limited:
            hasAccess = true
            print("🟡 Contacts: Limited access")
            
        @unknown default:
            throw ContactsError.accessDenied
        }
    }
    
    private func ensureAccess() async throws {
        if !hasAccess {
            try await requestAccess()
        }
    }
    
    // MARK: - Search
    
    // MARK: - Keys to Fetch

    private var allContactKeys: [CNKeyDescriptor] {
        [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactDepartmentNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactDatesKey as CNKeyDescriptor,
            CNContactSocialProfilesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor
        ]
    }

    /// Search for contacts by name (first, last, or nickname)
    func searchByName(_ query: String) async throws -> [DorisContact] {
        try await ensureAccess()

        let predicate = CNContact.predicateForContacts(matchingName: query)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: allContactKeys)
            print("👤 Contacts: Found \(contacts.count) matches for '\(query)'")
            return contacts.map { DorisContact(from: $0) }
        } catch {
            print("🔴 Contacts: Search error: \(error)")
            throw ContactsError.searchFailed
        }
    }
    
    /// Find contact with email - returns best match or nil
    func findEmail(for name: String) async throws -> String? {
        let contacts = try await searchByName(name)
        
        // No matches
        guard !contacts.isEmpty else {
            return nil
        }
        
        // Single match with email
        if contacts.count == 1, let email = contacts.first?.primaryEmail {
            return email
        }
        
        // Multiple matches - try to find exact name match
        let nameLower = name.lowercased()
        for contact in contacts {
            let fullName = "\(contact.firstName) \(contact.lastName)".lowercased()
            let firstMatch = contact.firstName.lowercased() == nameLower
            let nickMatch = contact.nickname?.lowercased() == nameLower
            
            if (firstMatch || nickMatch || fullName == nameLower), let email = contact.primaryEmail {
                return email
            }
        }
        
        // Return first contact's email as fallback
        return contacts.first?.primaryEmail
    }
    
    /// Find contact with phone - returns best match or nil
    func findPhone(for name: String) async throws -> String? {
        let contacts = try await searchByName(name)
        
        guard !contacts.isEmpty else {
            return nil
        }
        
        if contacts.count == 1, let phone = contacts.first?.primaryPhone {
            return phone
        }
        
        let nameLower = name.lowercased()
        for contact in contacts {
            let fullName = "\(contact.firstName) \(contact.lastName)".lowercased()
            let firstMatch = contact.firstName.lowercased() == nameLower
            let nickMatch = contact.nickname?.lowercased() == nameLower
            
            if (firstMatch || nickMatch || fullName == nameLower), let phone = contact.primaryPhone {
                return phone
            }
        }
        
        return contacts.first?.primaryPhone
    }
    
    /// Get all emails for a contact (when there are multiple)
    func getAllEmails(for name: String) async throws -> [(label: String?, email: String)] {
        let contacts = try await searchByName(name)
        
        var results: [(String?, String)] = []
        for contact in contacts {
            for email in contact.emails {
                results.append((email.label, email.value))
            }
        }
        
        return results
    }
    
    /// Format search results for display
    func formatSearchResults(_ contacts: [DorisContact]) -> String {
        guard !contacts.isEmpty else {
            return "No contacts found."
        }

        var result = "Found \(contacts.count) contact(s):\n"
        for contact in contacts {
            result += "- \(contact.displayName)"
            if let email = contact.primaryEmail {
                result += " <\(email)>"
            }
            if let phone = contact.primaryPhone {
                result += " \(phone)"
            }
            result += "\n"
        }
        return result
    }

    // MARK: - Reverse Lookups

    /// Search for contacts by email address
    func searchByEmail(_ email: String) async throws -> [DorisContact] {
        try await ensureAccess()

        let emailLower = email.lowercased()

        // CNContact doesn't have a predicate for email, so we fetch all and filter
        let request = CNContactFetchRequest(keysToFetch: allContactKeys)
        var matchingContacts: [DorisContact] = []

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                for emailAddress in contact.emailAddresses {
                    if (emailAddress.value as String).lowercased() == emailLower {
                        matchingContacts.append(DorisContact(from: contact))
                        break
                    }
                }
            }
            print("👤 Contacts: Found \(matchingContacts.count) matches for email '\(email)'")
            return matchingContacts
        } catch {
            print("🔴 Contacts: Email search error: \(error)")
            throw ContactsError.searchFailed
        }
    }

    /// Search for contacts by phone number
    func searchByPhone(_ phone: String) async throws -> [DorisContact] {
        try await ensureAccess()

        // Normalize phone number - remove all non-digits for comparison
        let normalizedSearch = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)

        let request = CNContactFetchRequest(keysToFetch: allContactKeys)
        var matchingContacts: [DorisContact] = []

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                for phoneNumber in contact.phoneNumbers {
                    let normalizedContact = phoneNumber.value.stringValue.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    // Match if the normalized numbers end with the same digits (handles country codes)
                    if normalizedContact.hasSuffix(normalizedSearch) || normalizedSearch.hasSuffix(normalizedContact) {
                        matchingContacts.append(DorisContact(from: contact))
                        break
                    }
                }
            }
            print("👤 Contacts: Found \(matchingContacts.count) matches for phone '\(phone)'")
            return matchingContacts
        } catch {
            print("🔴 Contacts: Phone search error: \(error)")
            throw ContactsError.searchFailed
        }
    }

    /// Search for contacts by organization/company name
    func searchByOrganization(_ organization: String) async throws -> [DorisContact] {
        try await ensureAccess()

        let orgLower = organization.lowercased()

        let request = CNContactFetchRequest(keysToFetch: allContactKeys)
        var matchingContacts: [DorisContact] = []

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                if contact.organizationName.lowercased().contains(orgLower) {
                    matchingContacts.append(DorisContact(from: contact))
                }
            }
            print("👤 Contacts: Found \(matchingContacts.count) matches for organization '\(organization)'")
            return matchingContacts
        } catch {
            print("🔴 Contacts: Organization search error: \(error)")
            throw ContactsError.searchFailed
        }
    }

    /// List all contacts (with optional limit)
    func listAllContacts(limit: Int = 100) async throws -> [DorisContact] {
        try await ensureAccess()

        let request = CNContactFetchRequest(keysToFetch: allContactKeys)
        request.sortOrder = .familyName
        var allContacts: [DorisContact] = []

        do {
            try store.enumerateContacts(with: request) { contact, stop in
                allContacts.append(DorisContact(from: contact))
                if allContacts.count >= limit {
                    stop.pointee = true
                }
            }
            print("👤 Contacts: Listed \(allContacts.count) contacts")
            return allContacts
        } catch {
            print("🔴 Contacts: List error: \(error)")
            throw ContactsError.searchFailed
        }
    }

    /// Get contacts with upcoming birthdays
    func getUpcomingBirthdays(withinDays days: Int = 30) async throws -> [(contact: DorisContact, daysUntil: Int)] {
        try await ensureAccess()

        let request = CNContactFetchRequest(keysToFetch: allContactKeys)
        var birthdayContacts: [(DorisContact, Int)] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                guard let birthday = contact.birthday else { return }

                // Create this year's birthday date
                var thisYearBirthday = birthday
                thisYearBirthday.year = calendar.component(.year, from: today)

                guard let birthdayDate = calendar.date(from: thisYearBirthday) else { return }

                let daysUntil = calendar.dateComponents([.day], from: today, to: birthdayDate).day ?? 0

                // Check if birthday is within range (including past birthdays this year for "today" case)
                if daysUntil >= 0 && daysUntil <= days {
                    birthdayContacts.append((DorisContact(from: contact), daysUntil))
                } else if daysUntil < 0 {
                    // Birthday already passed this year, check next year
                    thisYearBirthday.year = calendar.component(.year, from: today) + 1
                    if let nextYearDate = calendar.date(from: thisYearBirthday) {
                        let daysUntilNext = calendar.dateComponents([.day], from: today, to: nextYearDate).day ?? 0
                        if daysUntilNext <= days {
                            birthdayContacts.append((DorisContact(from: contact), daysUntilNext))
                        }
                    }
                }
            }

            // Sort by days until birthday
            birthdayContacts.sort { $0.1 < $1.1 }
            print("👤 Contacts: Found \(birthdayContacts.count) upcoming birthdays")
            return birthdayContacts
        } catch {
            print("🔴 Contacts: Birthday search error: \(error)")
            throw ContactsError.searchFailed
        }
    }

    // MARK: - Contact Creation

    /// Create a new contact
    func createContact(
        firstName: String,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        organization: String? = nil,
        jobTitle: String? = nil,
        address: (street: String?, city: String?, state: String?, postalCode: String?, country: String?)? = nil,
        birthday: DateComponents? = nil,
        note: String? = nil
    ) async throws -> DorisContact {
        try await ensureAccess()

        let newContact = CNMutableContact()
        newContact.givenName = firstName
        if let lastName = lastName {
            newContact.familyName = lastName
        }

        if let email = email {
            newContact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }

        if let phone = phone {
            newContact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
        }

        if let organization = organization {
            newContact.organizationName = organization
        }

        if let jobTitle = jobTitle {
            newContact.jobTitle = jobTitle
        }

        if let address = address {
            let postalAddress = CNMutablePostalAddress()
            if let street = address.street { postalAddress.street = street }
            if let city = address.city { postalAddress.city = city }
            if let state = address.state { postalAddress.state = state }
            if let postalCode = address.postalCode { postalAddress.postalCode = postalCode }
            if let country = address.country { postalAddress.country = country }
            newContact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: postalAddress)]
        }

        if let birthday = birthday {
            newContact.birthday = birthday
        }

        if let note = note {
            newContact.note = note
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(newContact, toContainerWithIdentifier: nil)

        do {
            try store.execute(saveRequest)
            print("👤 Contacts: Created contact '\(firstName) \(lastName ?? "")'")

            // Fetch the newly created contact to return it
            let contacts = try await searchByName(firstName)
            if let created = contacts.first(where: { $0.identifier == newContact.identifier }) {
                return created
            }
            // Fallback: return first match
            return contacts.first ?? DorisContact(from: newContact)
        } catch {
            print("🔴 Contacts: Create error: \(error)")
            throw ContactsError.createFailed(error.localizedDescription)
        }
    }

    // MARK: - Detailed Contact Info

    /// Get full details for a contact as formatted string
    func getFullContactDetails(_ contact: DorisContact) -> String {
        var details: [String] = []

        details.append("**\(contact.displayName)**")

        if let org = contact.organization {
            var orgLine = org
            if let title = contact.jobTitle {
                orgLine = "\(title) at \(org)"
            }
            details.append(orgLine)
        }

        if !contact.phones.isEmpty {
            details.append("")
            details.append("**Phone:**")
            for phone in contact.phones {
                let label = phone.label ?? "phone"
                details.append("  \(label): \(phone.value)")
            }
        }

        if !contact.emails.isEmpty {
            details.append("")
            details.append("**Email:**")
            for email in contact.emails {
                let label = email.label ?? "email"
                details.append("  \(label): \(email.value)")
            }
        }

        if !contact.addresses.isEmpty {
            details.append("")
            details.append("**Address:**")
            for address in contact.addresses {
                let label = address.label ?? "address"
                details.append("  \(label):")
                details.append("  \(address.formatted.replacingOccurrences(of: "\n", with: "\n  "))")
            }
        }

        if let birthday = contact.formattedBirthday {
            details.append("")
            details.append("**Birthday:** \(birthday)")
        }

        if !contact.socialProfiles.isEmpty {
            details.append("")
            details.append("**Social:**")
            for profile in contact.socialProfiles {
                details.append("  \(profile.service): @\(profile.username)")
            }
        }

        if !contact.urls.isEmpty {
            details.append("")
            details.append("**URLs:**")
            for url in contact.urls {
                let label = url.label ?? "url"
                details.append("  \(label): \(url.value)")
            }
        }

        if let note = contact.note {
            details.append("")
            details.append("**Notes:** \(note)")
        }

        return details.joined(separator: "\n")
    }
}

// MARK: - Models

struct DorisContact {
    let firstName: String
    let lastName: String
    let middleName: String?
    let nickname: String?
    let organization: String?
    let jobTitle: String?
    let department: String?
    let emails: [(label: String?, value: String)]
    let phones: [(label: String?, value: String)]
    let addresses: [DorisAddress]
    let birthday: DateComponents?
    let dates: [(label: String?, date: DateComponents)]
    let socialProfiles: [(service: String, username: String, url: String?)]
    let urls: [(label: String?, value: String)]
    let note: String?
    let identifier: String

    var displayName: String {
        if !firstName.isEmpty || !lastName.isEmpty {
            return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        } else if let nickname = nickname, !nickname.isEmpty {
            return nickname
        } else if let org = organization, !org.isEmpty {
            return org
        }
        return "Unknown"
    }

    var primaryEmail: String? {
        emails.first?.value
    }

    var primaryPhone: String? {
        phones.first?.value
    }

    var primaryAddress: DorisAddress? {
        addresses.first
    }

    var formattedBirthday: String? {
        guard let birthday = birthday else { return nil }
        var components: [String] = []
        if let month = birthday.month, let day = birthday.day {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            if let date = Calendar.current.date(from: birthday) {
                components.append(formatter.string(from: date))
            } else {
                components.append("\(month)/\(day)")
            }
        }
        if let year = birthday.year {
            components.append(String(year))
        }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }

    init(from cnContact: CNContact) {
        self.identifier = cnContact.identifier
        self.firstName = cnContact.givenName
        self.lastName = cnContact.familyName
        self.middleName = cnContact.middleName.isEmpty ? nil : cnContact.middleName
        self.nickname = cnContact.nickname.isEmpty ? nil : cnContact.nickname
        self.organization = cnContact.organizationName.isEmpty ? nil : cnContact.organizationName
        self.jobTitle = cnContact.jobTitle.isEmpty ? nil : cnContact.jobTitle
        self.department = cnContact.departmentName.isEmpty ? nil : cnContact.departmentName
        self.note = cnContact.note.isEmpty ? nil : cnContact.note
        self.birthday = cnContact.birthday

        self.emails = cnContact.emailAddresses.map { labeledValue in
            let label = labeledValue.label.flatMap { CNLabeledValue<NSString>.localizedString(forLabel: $0) }
            return (label, labeledValue.value as String)
        }

        self.phones = cnContact.phoneNumbers.map { labeledValue in
            let label = labeledValue.label.flatMap { CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0) }
            return (label, labeledValue.value.stringValue)
        }

        self.addresses = cnContact.postalAddresses.map { labeledValue in
            let label = labeledValue.label.flatMap { CNLabeledValue<CNPostalAddress>.localizedString(forLabel: $0) }
            return DorisAddress(from: labeledValue.value, label: label)
        }

        self.dates = cnContact.dates.map { labeledValue in
            let label = labeledValue.label.flatMap { CNLabeledValue<NSDateComponents>.localizedString(forLabel: $0) }
            return (label, labeledValue.value as DateComponents)
        }

        self.socialProfiles = cnContact.socialProfiles.map { labeledValue in
            let profile = labeledValue.value
            return (profile.service, profile.username, profile.urlString.isEmpty ? nil : profile.urlString)
        }

        self.urls = cnContact.urlAddresses.map { labeledValue in
            let label = labeledValue.label.flatMap { CNLabeledValue<NSString>.localizedString(forLabel: $0) }
            return (label, labeledValue.value as String)
        }
    }
}

struct DorisAddress {
    let label: String?
    let street: String
    let city: String
    let state: String
    let postalCode: String
    let country: String

    var formatted: String {
        var lines: [String] = []
        if !street.isEmpty { lines.append(street) }
        var cityLine = ""
        if !city.isEmpty { cityLine += city }
        if !state.isEmpty { cityLine += cityLine.isEmpty ? state : ", \(state)" }
        if !postalCode.isEmpty { cityLine += " \(postalCode)" }
        if !cityLine.isEmpty { lines.append(cityLine) }
        if !country.isEmpty { lines.append(country) }
        return lines.joined(separator: "\n")
    }

    init(from postalAddress: CNPostalAddress, label: String?) {
        self.label = label
        self.street = postalAddress.street
        self.city = postalAddress.city
        self.state = postalAddress.state
        self.postalCode = postalAddress.postalCode
        self.country = postalAddress.country
    }
}

enum ContactsError: LocalizedError {
    case accessDenied
    case searchFailed
    case notFound
    case createFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Contacts access denied. Enable in System Settings > Privacy & Security > Contacts."
        case .searchFailed:
            return "Failed to search contacts."
        case .notFound:
            return "Contact not found."
        case .createFailed(let reason):
            return "Failed to create contact: \(reason)"
        }
    }
}
