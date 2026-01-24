import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("currentUser") private var currentUser: String = "adam"
    @AppStorage("serverURL") private var serverURL: String = "http://100.125.207.74:8000"

    private let warmWhite = Color(red: 1.0, green: 0.973, blue: 0.941)

    private let users = [
        ("adam", "Adam"),
        ("gabby", "Gabby"),
        ("levi", "Levi"),
        ("dani", "Dani")
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "d1684e")
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // User Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("WHO'S USING DORIS?")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(warmWhite.opacity(0.6))
                                .tracking(1.5)

                            VStack(spacing: 0) {
                                ForEach(users, id: \.0) { user in
                                    Button(action: {
                                        currentUser = user.0
                                    }) {
                                        HStack {
                                            Text(user.1)
                                                .font(.system(size: 17))
                                                .foregroundColor(warmWhite)

                                            Spacer()

                                            if currentUser == user.0 {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(warmWhite)
                                                    .font(.system(size: 16, weight: .semibold))
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                    }

                                    if user.0 != users.last?.0 {
                                        Divider()
                                            .background(warmWhite.opacity(0.2))
                                    }
                                }
                            }
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(12)

                            Text("Doris will personalize responses based on who's talking.")
                                .font(.system(size: 13))
                                .foregroundColor(warmWhite.opacity(0.5))
                                .padding(.top, 4)
                        }

                        // Server URL (Advanced)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SERVER")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(warmWhite.opacity(0.6))
                                .tracking(1.5)

                            TextField("Server URL", text: $serverURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15))
                                .foregroundColor(warmWhite)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(12)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        }

                        Spacer()
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(warmWhite)
                }
            }
            .toolbarBackground(Color(hex: "d1684e"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

#Preview {
    SettingsView()
}
