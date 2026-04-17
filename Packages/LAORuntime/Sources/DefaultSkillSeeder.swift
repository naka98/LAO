import Foundation
import LAODomain
import LAOServices

public final class DefaultSkillSeeder: @unchecked Sendable {
    private let skillService: SkillService

    public init(skillService: SkillService) {
        self.skillService = skillService
    }

    /// Seed default skills for all roles if no skills exist yet.
    public func seedDefaultSkills() async {
        let existing = await skillService.listSkills()
        guard existing.isEmpty else { return }

        for entry in Self.defaultSkills {
            let skill = Skill(
                role: entry.role,
                name: entry.name,
                skillDescription: entry.description
            )
            _ = try? await skillService.createSkill(skill)
        }
    }

    // MARK: - Default Skill Definitions

    private struct SkillEntry {
        let role: AgentRole
        let name: String
        let description: String
    }

    private static let defaultSkills: [SkillEntry] = [
        // Planner
        SkillEntry(role: .planner, name: "아이디어 발상",
                   description: "브레인스토밍을 통해 창의적인 아이디어를 도출합니다"),
        SkillEntry(role: .planner, name: "컨셉 설계",
                   description: "아이디어를 구체적인 제품/서비스 컨셉으로 발전시킵니다"),
        SkillEntry(role: .planner, name: "사용자 시나리오",
                   description: "사용자 관점에서 기능 흐름과 시나리오를 설계합니다"),
        SkillEntry(role: .planner, name: "요구사항 정의",
                   description: "아이디어를 명확한 기능 요구사항으로 정리합니다"),

        // Designer
        SkillEntry(role: .designer, name: "UX 설계",
                   description: "사용자 경험을 중심으로 인터페이스 흐름을 설계합니다"),
        SkillEntry(role: .designer, name: "정보 구조 설계",
                   description: "콘텐츠와 기능의 구조를 체계적으로 설계합니다"),
        SkillEntry(role: .designer, name: "디자인 피드백",
                   description: "UI/UX 관점에서 디자인의 문제점과 개선안을 제시합니다"),

        // PM
        SkillEntry(role: .pm, name: "작업 분해",
                   description: "요구사항을 실행 가능한 세부 작업으로 분해합니다"),
        SkillEntry(role: .pm, name: "스프린트 계획",
                   description: "작업 우선순위를 정하고 스프린트 단위로 계획합니다"),
        SkillEntry(role: .pm, name: "리스크 평가",
                   description: "잠재적 위험 요소를 식별하고 대응 방안을 제시합니다"),
        SkillEntry(role: .pm, name: "우선순위 결정",
                   description: "비즈니스 가치와 긴급도를 기준으로 우선순위를 판단합니다"),

        // Dev
        SkillEntry(role: .dev, name: "코드 리뷰",
                   description: "코드의 품질, 버그, 개선점을 분석합니다"),
        SkillEntry(role: .dev, name: "아키텍처 설계",
                   description: "시스템 구조와 설계 패턴을 제안합니다"),
        SkillEntry(role: .dev, name: "디버깅",
                   description: "오류 원인을 분석하고 해결 방안을 제시합니다"),
        SkillEntry(role: .dev, name: "구현 계획",
                   description: "기능 구현의 단계별 접근 방법을 설계합니다"),

        // QA
        SkillEntry(role: .qa, name: "테스트 계획",
                   description: "테스트 시나리오와 케이스를 설계합니다"),
        SkillEntry(role: .qa, name: "버그 분석",
                   description: "버그의 원인, 영향, 재현 조건을 분석합니다"),
        SkillEntry(role: .qa, name: "품질 기준 정의",
                   description: "릴리스 품질 기준과 체크리스트를 수립합니다"),

        // Research
        SkillEntry(role: .research, name: "기술 조사",
                   description: "기술, 도구, 프레임워크를 조사하고 평가합니다"),
        SkillEntry(role: .research, name: "비교 분석",
                   description: "여러 대안을 비교하여 장단점을 분석합니다"),
        SkillEntry(role: .research, name: "트렌드 리서치",
                   description: "업계 트렌드와 최신 동향을 파악하여 보고합니다"),

        // Marketer
        SkillEntry(role: .marketer, name: "GTM 전략",
                   description: "제품의 시장 진입 전략과 론칭 계획을 수립합니다"),
        SkillEntry(role: .marketer, name: "포지셔닝 분석",
                   description: "경쟁 환경에서 제품의 차별화 포인트와 포지셔닝을 정의합니다"),
        SkillEntry(role: .marketer, name: "타겟 고객 분석",
                   description: "타겟 사용자 세그먼트와 페르소나를 분석합니다"),
        SkillEntry(role: .marketer, name: "메시지 전략",
                   description: "고객에게 전달할 핵심 가치와 커뮤니케이션 메시지를 설계합니다"),

        // Reviewer
        SkillEntry(role: .reviewer, name: "리스크 메모",
                   description: "의사결정의 잠재적 리스크와 부작용을 체계적으로 정리합니다"),
        SkillEntry(role: .reviewer, name: "반대 의견 제시",
                   description: "Devil's advocate로서 논의의 맹점과 반론을 제기합니다"),
        SkillEntry(role: .reviewer, name: "실현 가능성 검토",
                   description: "계획의 기술적·비즈니스적 실현 가능성을 비판적으로 평가합니다"),
    ]
}
