// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Produced by `bash scripts/generate-canon.sh` from the `sources:` frontmatter of
// every SKILL.md in this repo. To change what the landing page shelves, change a
// skill's `sources:` block and re-run that script — editing this file instead puts
// the page back to asserting provenance nothing in the repo produces, which is the
// drift issue #273 closed.
//
// `scripts/test-canon-coverage.sh` re-runs the generator and fails when this file
// disagrees with the frontmatter, so a stale copy cannot reach prod.

export interface CanonCitation {
	/** Skill directory name; its SKILL.md is at `${skill}/SKILL.md`. */
	skill: string;
	/** The `sources:` sub-key the skill declared this work under. */
	tier: "primary" | "secondary";
}

export interface CanonWork {
	/** The declared string, verbatim: "Title — Author". */
	full: string;
	title: string;
	author: string;
	/** Papers cite with `et al.` or a parenthesized year; books do not. */
	type: "book" | "paper";
	/** Every skill that declares this work, in skill-directory order. */
	citations: CanonCitation[];
}

/** Sorted by title, so the data carries no presentation opinion. */
export const canon: CanonWork[] = [
	{
		full: "A Philosophy of Software Design — John Ousterhout",
		title: "A Philosophy of Software Design",
		author: "John Ousterhout",
		type: "book",
		citations: [
			{ skill: "correct-course", tier: "secondary" },
			{ skill: "design-an-interface", tier: "primary" },
			{ skill: "improve-codebase-architecture", tier: "primary" },
			{ skill: "tdd", tier: "secondary" },
			{ skill: "write-a-prd", tier: "secondary" },
		],
	},
	{
		full: "Advanced Vitest Patterns — Epic Web Dev",
		title: "Advanced Vitest Patterns",
		author: "Epic Web Dev",
		type: "book",
		citations: [
			{ skill: "ts-audit", tier: "secondary" },
		],
	},
	{
		full: "Best Kept Secrets of Peer Code Review — Jason Cohen",
		title: "Best Kept Secrets of Peer Code Review",
		author: "Jason Cohen",
		type: "book",
		citations: [
			{ skill: "pre-merge", tier: "secondary" },
			{ skill: "visual-recap", tier: "primary" },
			{ skill: "walk-commits", tier: "secondary" },
		],
	},
	{
		full: "Clean Architecture — Robert C. Martin",
		title: "Clean Architecture",
		author: "Robert C. Martin",
		type: "book",
		citations: [
			{ skill: "improve-codebase-architecture", tier: "secondary" },
		],
	},
	{
		full: "Code Reading: The Open Source Perspective — Diomidis Spinellis",
		title: "Code Reading: The Open Source Perspective",
		author: "Diomidis Spinellis",
		type: "book",
		citations: [
			{ skill: "walk-commits", tier: "primary" },
		],
	},
	{
		full: "Continuous Delivery — Jez Humble & David Farley",
		title: "Continuous Delivery",
		author: "Jez Humble & David Farley",
		type: "book",
		citations: [
			{ skill: "closeout", tier: "secondary" },
			{ skill: "execute", tier: "secondary" },
			{ skill: "pre-merge", tier: "secondary" },
		],
	},
	{
		full: "Designing Web APIs — Jin, Sahni, Shevat",
		title: "Designing Web APIs",
		author: "Jin, Sahni, Shevat",
		type: "book",
		citations: [
			{ skill: "design-an-interface", tier: "secondary" },
			{ skill: "prd-to-issues", tier: "secondary" },
		],
	},
	{
		full: "Domain Modeling Made Functional — Scott Wlaschin",
		title: "Domain Modeling Made Functional",
		author: "Scott Wlaschin",
		type: "book",
		citations: [
			{ skill: "pre-merge", tier: "secondary" },
			{ skill: "tdd", tier: "secondary" },
		],
	},
	{
		full: "Domain Storytelling — Hofer & Schwentner",
		title: "Domain Storytelling",
		author: "Hofer & Schwentner",
		type: "book",
		citations: [
			{ skill: "shape", tier: "secondary" },
			{ skill: "ubiquitous-language", tier: "secondary" },
		],
	},
	{
		full: "Domain-Driven Design — Eric Evans",
		title: "Domain-Driven Design",
		author: "Eric Evans",
		type: "book",
		citations: [
			{ skill: "triage-issue", tier: "secondary" },
			{ skill: "ubiquitous-language", tier: "primary" },
		],
	},
	{
		full: "Encouraging Divergent Thinking in LLMs through Multi-Agent Debate — Liang et al. (EMNLP 2024)",
		title: "Encouraging Divergent Thinking in LLMs through Multi-Agent Debate",
		author: "Liang et al. (EMNLP 2024)",
		type: "paper",
		citations: [
			{ skill: "improve-pipeline", tier: "secondary" },
		],
	},
	{
		full: "Engineering a Safer World — Nancy Leveson",
		title: "Engineering a Safer World",
		author: "Nancy Leveson",
		type: "book",
		citations: [
			{ skill: "pre-merge", tier: "secondary" },
		],
	},
	{
		full: "Envisioning Information — Edward Tufte",
		title: "Envisioning Information",
		author: "Edward Tufte",
		type: "book",
		citations: [
			{ skill: "visual-recap", tier: "secondary" },
		],
	},
	{
		full: "Exploring Requirements — Gause & Weinberg",
		title: "Exploring Requirements",
		author: "Gause & Weinberg",
		type: "book",
		citations: [
			{ skill: "shape", tier: "primary" },
		],
	},
	{
		full: "Extreme Programming Explained — Kent Beck",
		title: "Extreme Programming Explained",
		author: "Kent Beck",
		type: "book",
		citations: [
			{ skill: "execute", tier: "secondary" },
			{ skill: "prototype", tier: "primary" },
			{ skill: "research", tier: "secondary" },
			{ skill: "tdd", tier: "secondary" },
		],
	},
	{
		full: "Growing Object-Oriented Software, Guided by Tests — Freeman & Pryce",
		title: "Growing Object-Oriented Software, Guided by Tests",
		author: "Freeman & Pryce",
		type: "book",
		citations: [
			{ skill: "execute", tier: "secondary" },
			{ skill: "pre-merge", tier: "secondary" },
			{ skill: "tdd", tier: "secondary" },
		],
	},
	{
		full: "Improving Factuality and Reasoning in Language Models through Multiagent Debate — Du et al. (2023)",
		title: "Improving Factuality and Reasoning in Language Models through Multiagent Debate",
		author: "Du et al. (2023)",
		type: "paper",
		citations: [
			{ skill: "improve-pipeline", tier: "secondary" },
		],
	},
	{
		full: "Introduction to Software Testing — Ammann & Offutt",
		title: "Introduction to Software Testing",
		author: "Ammann & Offutt",
		type: "book",
		citations: [
			{ skill: "tdd", tier: "secondary" },
		],
	},
	{
		full: "Living Documentation — Cyrille Martraire",
		title: "Living Documentation",
		author: "Cyrille Martraire",
		type: "book",
		citations: [
			{ skill: "compound", tier: "primary" },
			{ skill: "prd-to-issues", tier: "secondary" },
			{ skill: "ubiquitous-language", tier: "secondary" },
		],
	},
	{
		full: "Mocking Techniques in Vitest — Epic Web Dev",
		title: "Mocking Techniques in Vitest",
		author: "Epic Web Dev",
		type: "book",
		citations: [
			{ skill: "ts-audit", tier: "secondary" },
		],
	},
	{
		full: "Noise: A Flaw in Human Judgment — Daniel Kahneman, Olivier Sibony & Cass Sunstein",
		title: "Noise: A Flaw in Human Judgment",
		author: "Daniel Kahneman, Olivier Sibony & Cass Sunstein",
		type: "book",
		citations: [
			{ skill: "pre-merge", tier: "secondary" },
		],
	},
	{
		full: "On Writing Well — William Zinsser",
		title: "On Writing Well",
		author: "William Zinsser",
		type: "book",
		citations: [
			{ skill: "handoff", tier: "secondary" },
		],
	},
	{
		full: "Peer Review on Open-Source Software Projects — Peter C. Rigby",
		title: "Peer Review on Open-Source Software Projects",
		author: "Peter C. Rigby",
		type: "paper",
		citations: [
			{ skill: "walk-commits", tier: "secondary" },
		],
	},
	{
		full: "Refactoring — Martin Fowler",
		title: "Refactoring",
		author: "Martin Fowler",
		type: "book",
		citations: [
			{ skill: "request-refactor-plan", tier: "primary" },
			{ skill: "tdd", tier: "secondary" },
		],
	},
	{
		full: "Release It! — Michael Nygard",
		title: "Release It!",
		author: "Michael Nygard",
		type: "book",
		citations: [
			{ skill: "execute", tier: "secondary" },
			{ skill: "improve-pipeline", tier: "secondary" },
			{ skill: "pre-merge", tier: "secondary" },
			{ skill: "shape", tier: "secondary" },
		],
	},
	{
		full: "Shape Up — Ryan Singer",
		title: "Shape Up",
		author: "Ryan Singer",
		type: "book",
		citations: [
			{ skill: "create-milestone", tier: "primary" },
			{ skill: "write-a-prd", tier: "primary" },
		],
	},
	{
		full: "Smart Brevity — Jim VandeHei, Mike Allen, Roy Schwartz",
		title: "Smart Brevity",
		author: "Jim VandeHei, Mike Allen, Roy Schwartz",
		type: "book",
		citations: [
			{ skill: "handoff", tier: "secondary" },
		],
	},
	{
		full: "Software Estimation — Steve McConnell",
		title: "Software Estimation",
		author: "Steve McConnell",
		type: "book",
		citations: [
			{ skill: "compound", tier: "secondary" },
			{ skill: "prd-to-issues", tier: "secondary" },
			{ skill: "research", tier: "primary" },
			{ skill: "write-a-prd", tier: "secondary" },
		],
	},
	{
		full: "Software Requirements — Karl Wiegers & Joy Beatty",
		title: "Software Requirements",
		author: "Karl Wiegers & Joy Beatty",
		type: "book",
		citations: [
			{ skill: "prd-to-issues", tier: "secondary" },
			{ skill: "pre-merge", tier: "secondary" },
			{ skill: "write-a-prd", tier: "secondary" },
		],
	},
	{
		full: "TDD By Example — Kent Beck",
		title: "TDD By Example",
		author: "Kent Beck",
		type: "book",
		citations: [
			{ skill: "tdd", tier: "primary" },
		],
	},
	{
		full: "Testing Fundamentals — Kent C. Dodds",
		title: "Testing Fundamentals",
		author: "Kent C. Dodds",
		type: "book",
		citations: [
			{ skill: "ts-audit", tier: "secondary" },
		],
	},
	{
		full: "The Checklist Manifesto — Atul Gawande",
		title: "The Checklist Manifesto",
		author: "Atul Gawande",
		type: "book",
		citations: [
			{ skill: "closeout", tier: "secondary" },
			{ skill: "compound", tier: "secondary" },
			{ skill: "execute", tier: "secondary" },
			{ skill: "pre-merge", tier: "secondary" },
			{ skill: "research", tier: "secondary" },
			{ skill: "shape", tier: "secondary" },
		],
	},
	{
		full: "The Design of Everyday Things — Don Norman",
		title: "The Design of Everyday Things",
		author: "Don Norman",
		type: "book",
		citations: [
			{ skill: "closeout", tier: "primary" },
			{ skill: "handoff", tier: "primary" },
			{ skill: "improve-pipeline", tier: "secondary" },
			{ skill: "prototype", tier: "secondary" },
			{ skill: "visual-recap", tier: "primary" },
		],
	},
	{
		full: "The Fifth Discipline — Peter Senge",
		title: "The Fifth Discipline",
		author: "Peter Senge",
		type: "book",
		citations: [
			{ skill: "compound", tier: "secondary" },
			{ skill: "improve-pipeline", tier: "secondary" },
		],
	},
	{
		full: "The Mom Test — Rob Fitzpatrick",
		title: "The Mom Test",
		author: "Rob Fitzpatrick",
		type: "book",
		citations: [
			{ skill: "shape", tier: "secondary" },
		],
	},
	{
		full: "The Pragmatic Programmer — Andrew Hunt & David Thomas",
		title: "The Pragmatic Programmer",
		author: "Andrew Hunt & David Thomas",
		type: "book",
		citations: [
			{ skill: "prd-to-issues", tier: "primary" },
			{ skill: "prototype", tier: "secondary" },
		],
	},
	{
		full: "The Programmer's Brain — Felienne Hermans",
		title: "The Programmer's Brain",
		author: "Felienne Hermans",
		type: "book",
		citations: [
			{ skill: "prd-to-issues", tier: "secondary" },
		],
	},
	{
		full: "The Twelve-Factor App — Adam Wiggins",
		title: "The Twelve-Factor App",
		author: "Adam Wiggins",
		type: "book",
		citations: [
			{ skill: "execute", tier: "secondary" },
			{ skill: "pre-merge", tier: "secondary" },
		],
	},
	{
		full: "The Visual Display of Quantitative Information — Edward Tufte",
		title: "The Visual Display of Quantitative Information",
		author: "Edward Tufte",
		type: "book",
		citations: [
			{ skill: "visual-recap", tier: "secondary" },
		],
	},
	{
		full: "Thinking in Bets — Annie Duke",
		title: "Thinking in Bets",
		author: "Annie Duke",
		type: "book",
		citations: [
			{ skill: "compound", tier: "secondary" },
			{ skill: "create-milestone", tier: "secondary" },
			{ skill: "improve-pipeline", tier: "secondary" },
			{ skill: "shape", tier: "secondary" },
			{ skill: "write-a-prd", tier: "secondary" },
		],
	},
	{
		full: "Thinking in Systems — Donella Meadows",
		title: "Thinking in Systems",
		author: "Donella Meadows",
		type: "book",
		citations: [
			{ skill: "closeout", tier: "primary" },
			{ skill: "compound", tier: "secondary" },
			{ skill: "correct-course", tier: "primary" },
			{ skill: "create-milestone", tier: "secondary" },
			{ skill: "improve-pipeline", tier: "primary" },
			{ skill: "shape", tier: "secondary" },
			{ skill: "triage-issue", tier: "primary" },
			{ skill: "visual-recap", tier: "secondary" },
			{ skill: "write-a-prd", tier: "secondary" },
		],
	},
	{
		full: "Total TypeScript — Matt Pocock",
		title: "Total TypeScript",
		author: "Matt Pocock",
		type: "book",
		citations: [
			{ skill: "ts-audit", tier: "primary" },
		],
	},
	{
		full: "Unit Testing — Vladimir Khorikov",
		title: "Unit Testing",
		author: "Vladimir Khorikov",
		type: "book",
		citations: [
			{ skill: "tdd", tier: "secondary" },
		],
	},
	{
		full: "Why Programs Fail — Andreas Zeller",
		title: "Why Programs Fail",
		author: "Andreas Zeller",
		type: "book",
		citations: [
			{ skill: "triage-issue", tier: "secondary" },
		],
	},
	{
		full: "Writing Effective Use Cases — Alistair Cockburn",
		title: "Writing Effective Use Cases",
		author: "Alistair Cockburn",
		type: "book",
		citations: [
			{ skill: "write-a-prd", tier: "secondary" },
		],
	},
];
