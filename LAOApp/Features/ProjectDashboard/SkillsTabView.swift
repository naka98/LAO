import LAODomain
import LAOServices
import SwiftUI

struct SkillsTabView: View {
    let container: AppContainer
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var skills: [Skill] = []
    @State private var showingNewSkill = false
    @State private var editingSkill: Skill?

    // Form state
    @State private var formRole: AgentRole = .pm
    @State private var formName = ""
    @State private var formDescription = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack {
                    if !skills.isEmpty {
                        Text(lang.skills.skillCountFormat(skills.count))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(theme.foregroundTertiary)
                    }

                    Spacer()

                    Button {
                        showingNewSkill = true
                    } label: {
                        Label(lang.skills.addSkill, systemImage: "plus")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }

                // Skills grouped by role
                ForEach(AgentRole.allCases) { role in
                    let roleSkills = skills.filter { $0.role == role }
                    if !roleSkills.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(role.rawValue.uppercased())
                                    .font(AppTheme.Typography.caption.weight(.semibold))
                                    .foregroundStyle(theme.foregroundTertiary)
                                Text("\(roleSkills.count)")
                                    .font(AppTheme.Typography.detail)
                                    .foregroundStyle(theme.foregroundTertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(theme.neutralBadgeFill))
                            }

                            VStack(spacing: 10) {
                                ForEach(roleSkills) { skill in
                                    skillCard(skill)
                                }
                            }
                        }
                    }
                }

                if skills.isEmpty {
                    SurfaceCard {
                        VStack(spacing: 12) {
                            Image(systemName: "star.circle")
                                .font(AppTheme.Typography.pageTitle)
                                .foregroundStyle(theme.foregroundMuted)
                            Text(lang.skills.noSkillsTitle)
                                .font(AppTheme.Typography.heading)
                            Text(lang.skills.noSkillsDescription)
                                .font(AppTheme.Typography.label)
                                .foregroundStyle(theme.foregroundSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }
            }
            .padding(24)
        }
        .laoWindowBackground()
        .task { await loadSkills() }
        .sheet(isPresented: $showingNewSkill) {
            skillFormSheet(editing: nil)
        }
        .sheet(item: $editingSkill) { skill in
            skillFormSheet(editing: skill)
        }
    }

    // MARK: - Skill Card

    private func skillCard(_ skill: Skill) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(skill.name)
                            .font(AppTheme.Typography.heading)
                        Text(skill.role.rawValue.uppercased())
                            .font(AppTheme.Typography.detail)
                            .foregroundStyle(theme.foregroundTertiary)
                    }
                    Spacer()
                    Button {
                        editingSkill = skill
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        Task { await deleteSkill(id: skill.id) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(theme.criticalAccent)
                    }
                    .buttonStyle(.borderless)
                }

                if !skill.skillDescription.isEmpty {
                    Text(skill.skillDescription)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Form Sheet

    private func skillFormSheet(editing skill: Skill?) -> some View {
        let isEditing = skill != nil

        return VStack(spacing: 20) {
            HStack {
                Image(systemName: isEditing ? "pencil.circle.fill" : "star.circle.fill")
                    .font(AppTheme.Typography.sectionTitle)
                    .foregroundStyle(theme.accentPrimary)
                Text(isEditing ? lang.skills.editSkill : lang.skills.newSkill)
                    .font(AppTheme.Typography.cardTitle.weight(.bold))
            }

            VStack(alignment: .leading, spacing: 12) {
                Picker(lang.skills.role, selection: $formRole) {
                    ForEach(AgentRole.allCases) { role in
                        Text(role.rawValue.uppercased()).tag(role)
                    }
                }

                TextField(lang.skills.skillName, text: $formName)
                    .textFieldStyle(.roundedBorder)

                TextField(lang.skills.description_, text: $formDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }

            HStack {
                Button(lang.common.cancel) {
                    showingNewSkill = false
                    editingSkill = nil
                    resetForm()
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button(isEditing ? lang.common.save : lang.common.create) {
                    Task {
                        if let skill {
                            await updateSkill(skill)
                        } else {
                            await createSkill()
                        }
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: AppTheme.SheetWidth.standard)
        .onAppear {
            if let skill {
                formRole = skill.role
                formName = skill.name
                formDescription = skill.skillDescription
            } else {
                resetForm()
            }
        }
    }

    // MARK: - Helpers

    private func resetForm() {
        formRole = .pm
        formName = ""
        formDescription = ""
    }

    // MARK: - CRUD

    private func loadSkills() async {
        skills = await container.skillService.listSkills()
    }

    private func createSkill() async {
        let skill = Skill(
            role: formRole,
            name: formName.trimmingCharacters(in: .whitespaces),
            skillDescription: formDescription
        )
        do {
            let created = try await container.skillService.createSkill(skill)
            skills.append(created)
            showingNewSkill = false
            resetForm()
        } catch {
            container.bannerState.show(.critical(lang.skills.createFailed, message: error.localizedDescription))
        }
    }

    private func updateSkill(_ original: Skill) async {
        var updated = original
        updated.role = formRole
        updated.name = formName.trimmingCharacters(in: .whitespaces)
        updated.skillDescription = formDescription
        do {
            try await container.skillService.updateSkill(updated)
            if let idx = skills.firstIndex(where: { $0.id == original.id }) {
                skills[idx] = updated
            }
            editingSkill = nil
            resetForm()
        } catch {
            container.bannerState.show(.critical(lang.skills.updateFailed, message: error.localizedDescription))
        }
    }

    private func deleteSkill(id: UUID) async {
        do {
            try await container.skillService.deleteSkill(id: id)
            skills.removeAll(where: { $0.id == id })
        } catch {
            container.bannerState.show(.critical(lang.skills.deleteFailed, message: error.localizedDescription))
        }
    }
}
