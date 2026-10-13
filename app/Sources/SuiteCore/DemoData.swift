import Foundation

/// Built-in sample data for screenshot mode and previews. No engine needed.
public enum DemoData {
    public static let runId = "r_7f3c2a"
    public static let goal = "Launch a company selling a home robot that folds laundry"

    public static let agents: [AgentInfo] = [
        AgentInfo(id: "ceo", name: "CEO", role: "Breaks the goal into tasks, sets priorities and writes the final report.",
                  skills: ["strategy"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "researcher", name: "Researcher", role: "Finds and weighs evidence: markets, competitors, papers and prior art.",
                  skills: ["research", "strategy"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "marketer", name: "Marketer", role: "Positioning, messaging, channels and launch plans.",
                  skills: ["marketing"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "product", name: "Product Manager", role: "Turns needs into requirements, scope and roadmaps.",
                  skills: ["product", "strategy"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "swe", name: "Software Engineer", role: "Writes and tests code: apps, services, tooling and firmware glue.",
                  skills: ["software", "ai"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "hardware", name: "Hardware Engineer", role: "Mechanisms, electronics, BOMs and design for manufacture.",
                  skills: ["hardware", "robotics"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "robotics", name: "Robotics Engineer", role: "Perception, planning and control for machines that move.",
                  skills: ["robotics", "hardware", "ai"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "ai", name: "AI Scientist", role: "Models, datasets, training plans and evaluation.",
                  skills: ["ai", "research", "software"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "math", name: "Mathematician", role: "Models, estimates and proofs; checks the numbers.",
                  skills: ["math", "physics"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "physics", name: "Physicist", role: "Physical modelling, simulation and sanity checks.",
                  skills: ["physics", "math", "hardware"], variants: ["opus-high", "sonnet-medium", "haiku"]),
        AgentInfo(id: "reviewer", name: "Reviewer", role: "Scores every result from 0 to 1 with a short rationale.",
                  skills: [], variants: ["sonnet-medium"], routable: false),
    ]

    public static let tasks: [SuiteTask] = [
        SuiteTask(id: "t_01", runId: runId, seq: 1, title: "Size the home laundry-robot market",
                  description: "Estimate TAM/SAM/SOM for a countertop robot that folds laundry in US and EU homes. Cite sources and state assumptions.",
                  kind: "research", status: .done, agent: "researcher", variant: "sonnet-medium",
                  summary: "SAM of about $3.1B across 38M dual-income households; early adopters are time-poor families earning over $150k. Willingness to pay clusters at $900–$1,400.",
                  outputPath: "workspace/tasks/01-size-the-market.md", judgeScore: 0.86,
                  judgeRationale: "Clear bottom-up model with cited household data; SOM assumptions are a little optimistic.",
                  userRating: 1, costUsd: 0.21),
        SuiteTask(id: "t_02", runId: runId, seq: 2, title: "Choose positioning and pricing",
                  description: "Pick a beachhead segment, a price point and a business model (hardware margin vs. subscription).",
                  kind: "strategy", status: .done, agent: "marketer", variant: "opus-high",
                  summary: "Lead with ‘get your Sunday back’ for busy families. $1,199 device plus an optional $12/month care plan; target 38% hardware margin by unit 10k.",
                  outputPath: "workspace/tasks/02-positioning-and-pricing.md", judgeScore: 0.81,
                  judgeRationale: "Well argued and consistent with the market sizing; the churn assumption for the care plan needs support.",
                  costUsd: 0.34),
        SuiteTask(id: "t_03", runId: runId, seq: 3, title: "Write v1 product requirements",
                  description: "Define what v1 must fold, how fast, its footprint, noise and safety limits, and what is out of scope.",
                  kind: "product", status: .done, agent: "product", variant: "opus-high",
                  summary: "v1 folds T-shirts, towels and trousers at 25 s per item, fits a 60 cm counter, under 45 dB. Fitted sheets and delicates are out of scope.",
                  outputPath: "workspace/tasks/03-product-requirements.md", judgeScore: 0.91,
                  judgeRationale: "Specific, testable requirements with explicit non-goals. Excellent.",
                  costUsd: 0.29),
        SuiteTask(id: "t_04", runId: runId, seq: 4, title: "Design the gripper and folding mechanism",
                  description: "Propose a mechanism that can grasp, flatten and fold garments within the v1 envelope; estimate BOM.",
                  kind: "hardware", status: .done, agent: "hardware", variant: "sonnet-medium",
                  summary: "Two 4-DOF arms with soft pinch grippers over a vacuum flattening bed. Estimated BOM $410 at 5k units.",
                  outputPath: "workspace/tasks/04-gripper-design.md", judgeScore: 0.64,
                  judgeRationale: "Plausible concept, but the vacuum bed's power draw and noise are not reconciled with the 45 dB requirement.",
                  userRating: 0, costUsd: 0.18),
        SuiteTask(id: "t_05", runId: runId, seq: 5, title: "Model fabric behaviour for fold planning",
                  description: "Choose a cloth model that is fast enough to plan folds on-device.",
                  kind: "physics", status: .done, agent: "physics", variant: "haiku",
                  summary: "Mass-spring model with 400 nodes runs at 30 Hz on the target SoC; good enough for towels, weak on knits.",
                  outputPath: "workspace/tasks/05-fabric-model.md", judgeScore: 0.72,
                  judgeRationale: "Reasonable trade-off; validation plan is thin.", costUsd: 0.03),
        SuiteTask(id: "t_06", runId: runId, seq: 6, title: "Plan the perception and manipulation stack",
                  description: "Sensors, software architecture and control loop for grasp → flatten → fold.",
                  kind: "robotics", status: .done, agent: "robotics", variant: "sonnet-medium",
                  summary: "Two RGB-D cameras, garment-corner detection, then scripted fold primitives with visual servoing. ROS 2 on an 8-core ARM board.",
                  outputPath: "workspace/tasks/06-perception-stack.md", judgeScore: 0.83,
                  judgeRationale: "Practical architecture that reuses proven fold primitives.", costUsd: 0.22),
        SuiteTask(id: "t_07", runId: runId, seq: 7, title: "Pick a cloth-recognition model and dataset",
                  description: "Select a model for garment type and corner detection, and a plan to collect training data.",
                  kind: "ai", status: .done, agent: "ai", variant: "sonnet-medium",
                  summary: "Fine-tune a small vision transformer on 40k labelled images; start from public cloth datasets and add 5k in-house captures.",
                  outputPath: "workspace/tasks/07-cloth-model.md", judgeScore: 0.88,
                  judgeRationale: "Concrete data plan and a sensible model size for the hardware.", userRating: 1, costUsd: 0.19),
        SuiteTask(id: "t_08", runId: runId, seq: 8, title: "Estimate unit economics",
                  description: "Combine BOM, assembly, logistics and support into contribution margin per unit and per subscriber.",
                  kind: "math", status: .done, agent: "math", variant: "haiku",
                  summary: "Contribution margin $372 per unit at $1,199; care plan adds $96/yr at 70% attach. Break-even at 21k units.",
                  outputPath: "workspace/tasks/08-unit-economics.md", judgeScore: 0.77,
                  judgeRationale: "Arithmetic checks out; sensitivity table would help.", costUsd: 0.02),
        SuiteTask(id: "t_09", runId: runId, seq: 9, title: "Build the pre-order landing page",
                  description: "A one-page site with the pitch, a demo GIF placeholder and a $99 refundable pre-order form.",
                  kind: "software", status: .done, agent: "swe", variant: "haiku",
                  summary: "Static site with Stripe Checkout in test mode, waitlist export to CSV, and a privacy page.",
                  outputPath: "workspace/tasks/09-landing-page/README.md", judgeScore: 0.79,
                  judgeRationale: "Works end to end in test mode; copy could be tighter.", costUsd: 0.06),
        SuiteTask(id: "t_10", runId: runId, seq: 10, title: "Draft the 90-day go-to-market plan",
                  description: "Channels, launch sequence and targets for the first 90 days of pre-orders.",
                  kind: "marketing", status: .done, agent: "marketer", variant: "haiku",
                  summary: "Creator demos on TikTok and YouTube, a Kickstarter-style pre-order push, and a 500-home beta in Austin. Target 3,000 pre-orders.",
                  outputPath: "workspace/tasks/10-go-to-market.md", judgeScore: 0.69,
                  judgeRationale: "Good channel choices; targets lack a funnel model.", costUsd: 0.03),
    ]

    public static let samples: [String: [String: Double]] = [
        "t_03": ["product": 0.84, "marketer": 0.61],
        "t_04": ["hardware": 0.71, "robotics": 0.66, "physics": 0.42],
        "t_07": ["ai": 0.79, "swe": 0.58, "robotics": 0.52, "researcher": 0.47, "math": 0.33],
    ]

    public static let similar: [String: [SimilarTask]] = [
        "t_04": [
            SimilarTask(taskId: "t_s1", title: "Design a soft gripper for picking up towels", kind: "robotics",
                        agent: "hardware", variant: "sonnet-medium", reward: 0.88, similarity: 0.61),
            SimilarTask(taskId: "t_s2", title: "Choose the folding mechanism and actuators", kind: "hardware",
                        agent: "hardware", variant: "opus-high", reward: 0.82, similarity: 0.47),
            SimilarTask(taskId: "t_s3", title: "Gripper force control for delicate fabrics", kind: "robotics",
                        agent: "robotics", variant: "sonnet-medium", reward: 0.74, similarity: 0.33),
        ],
    ]

    public static let report = """
    # Laundry-folding home robot: launch plan

    **Bottom line:** there is a credible $3.1B serviceable market among time-poor, dual-income households. A $1,199 countertop robot with an optional $12/month care plan can reach a **38% hardware margin** by unit 10,000 and break even at about **21k units**.

    ## What we decided
    - **Beachhead:** busy families in the US who already pay for cleaning help.
    - **Product:** folds T-shirts, towels and trousers at 25 s per item; fits a 60 cm counter; under 45 dB.
    - **Tech:** two soft-gripper arms, two RGB-D cameras, a small vision transformer for garment and corner detection.

    ## Open risks
    1. The vacuum flattening bed may break the noise budget. *Hardware is re-checking this.*
    2. Knitwear folds poorly with the current cloth model.
    3. Care-plan churn is assumed, not measured.

    ## Next 90 days
    - Beta with 500 homes in Austin, then a pre-order push aiming for 3,000 deposits.
    - Collect 5k in-house garment images to fine-tune the recognition model.
    """

    public static let runs: [RunSummary] = [
        RunSummary(id: runId, goal: goal, status: "done", createdAt: "2026-10-13T16:42:00Z", spentUsd: 1.57, taskCount: 10, mock: false,
                   report: report, workspace: "/Users/demo/Library/Application Support/Suite of Agents/runs/\(runId)/workspace"),
        RunSummary(id: "r_51ab90", goal: "Open a specialty coffee subscription for remote teams", status: "budget",
                   createdAt: "2026-10-12T16:10:00Z", spentUsd: 2.00, taskCount: 14),
        RunSummary(id: "r_2c71d4", goal: "Design a low-cost soil sensor for smallholder farms", status: "done",
                   createdAt: "2026-10-11T11:05:00Z", spentUsd: 1.12, taskCount: 9),
        RunSummary(id: "r_0e9d13", goal: "Write a study plan for learning quantum error correction", status: "canceled",
                   createdAt: "2026-10-10T20:31:00Z", spentUsd: 0.18, taskCount: 3, mock: true),
    ]

    public static var bandit: BanditSnapshot {
        var routing: [RoutingArm] = []
        // Deterministic pseudo-random but plausible posteriors: an agent's main skill scores best.
        for agent in agents where agent.routable {
            for (i, kind) in agent.skills.enumerated() {
                let seed = Double((agent.id.unicodeScalars.map { Int($0.value) }.reduce(0, +) * 31 + kind.count * 17) % 100) / 100
                let mean = i == 0 ? 0.74 + seed * 0.16 : 0.38 + seed * 0.3
                let n = i == 0 ? 9 + Int(seed * 14) : 1 + Int(seed * 6)
                let a = 1 + mean * Double(n), b = 1 + (1 - mean) * Double(n)
                routing.append(RoutingArm(kind: kind, agent: agent.id, alpha: a, beta: b, mean: a / (a + b), n: n))
            }
        }
        var variants: [VariantArm] = []
        let profile: [String: (Double, Int)] = ["opus-high": (0.84, 6), "sonnet-medium": (0.78, 14), "haiku": (0.66, 9)]
        for (idx, agent) in agents.enumerated() where agent.routable {
            for v in agent.variants {
                let (m, n) = profile[v] ?? (0.5, 2)
                let jitter = Double((idx * 7 + v.count * 3) % 11) / 100 - 0.05
                let mean = min(0.95, max(0.2, m + jitter))
                let nn = n + (idx % 4)
                let a = 1 + mean * Double(nn), b = 1 + (1 - mean) * Double(nn)
                variants.append(VariantArm(agent: agent.id, variant: v, alpha: a, beta: b, mean: a / (a + b), n: nn))
            }
        }
        return BanditSnapshot(kinds: KindCatalog.defaults.map(\.id), routing: routing, variants: variants)
    }
}
