from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle,
    PageBreak, KeepTogether, HRFlowable
)


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "output" / "pdf" / "vex_competitive_rating_specification.pdf"
OUT.parent.mkdir(parents=True, exist_ok=True)

NAVY = colors.HexColor("#102A43")
BLUE = colors.HexColor("#1769AA")
CYAN = colors.HexColor("#18A0AE")
INK = colors.HexColor("#243B53")
MUTED = colors.HexColor("#627D98")
PALE = colors.HexColor("#EAF4F8")
GOLD = colors.HexColor("#D99A18")
WHITE = colors.white
LIGHT = colors.HexColor("#F6F9FC")
RED = colors.HexColor("#C43D3D")


class VCRDoc(BaseDocTemplate):
    def __init__(self, filename):
        super().__init__(
            filename, pagesize=letter,
            leftMargin=0.68 * inch, rightMargin=0.68 * inch,
            topMargin=0.68 * inch, bottomMargin=0.60 * inch,
            title="VEX Competitive Rating (VCR) - Ranking System Specification",
            author="VEX V5 Ranking Project",
            subject="Team and event ranking algorithm for VEX V5 Robotics Competition",
        )
        frame = Frame(self.leftMargin, self.bottomMargin, self.width, self.height,
                      id="main", leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
        self.addPageTemplates(PageTemplate(id="body", frames=[frame], onPage=self.decorate))

    def decorate(self, canvas, doc):
        canvas.saveState()
        page_no = canvas.getPageNumber()
        if page_no > 1:
            x_left = 0.68 * inch
            x_right = letter[0] - 0.68 * inch
            canvas.setStrokeColor(colors.HexColor("#D9E2EC"))
            canvas.setLineWidth(0.5)
            canvas.line(x_left, letter[1] - 0.42 * inch, x_right, letter[1] - 0.42 * inch)
            canvas.setFont("Helvetica-Bold", 8)
            canvas.setFillColor(BLUE)
            canvas.drawString(x_left, letter[1] - 0.30 * inch, "VEX COMPETITIVE RATING")
            canvas.setFont("Helvetica", 8)
            canvas.setFillColor(MUTED)
            canvas.drawRightString(x_right, 0.34 * inch, f"PAGE {page_no}")
            canvas.drawString(x_left, 0.34 * inch, "Technical specification | Version 1.0")
        canvas.restoreState()


styles = getSampleStyleSheet()
styles.add(ParagraphStyle("TitleBig", parent=styles["Title"], fontName="Helvetica-Bold",
                          fontSize=30, leading=33, textColor=WHITE, alignment=TA_LEFT,
                          spaceAfter=12))
styles.add(ParagraphStyle("Subtitle", parent=styles["Normal"], fontName="Helvetica",
                          fontSize=13, leading=18, textColor=colors.HexColor("#D9F0F2")))
styles.add(ParagraphStyle("H1x", parent=styles["Heading1"], fontName="Helvetica-Bold",
                          fontSize=18, leading=22, textColor=NAVY, spaceBefore=5, spaceAfter=9))
styles.add(ParagraphStyle("H2x", parent=styles["Heading2"], fontName="Helvetica-Bold",
                          fontSize=12, leading=15, textColor=BLUE, spaceBefore=9, spaceAfter=5))
styles.add(ParagraphStyle("Bodyx", parent=styles["BodyText"], fontName="Helvetica",
                          fontSize=9.3, leading=13.2, textColor=INK, spaceAfter=6))
styles.add(ParagraphStyle("Small", parent=styles["BodyText"], fontName="Helvetica",
                          fontSize=7.6, leading=10.2, textColor=INK))
styles.add(ParagraphStyle("Tiny", parent=styles["BodyText"], fontName="Helvetica",
                          fontSize=6.8, leading=8.5, textColor=INK))
styles.add(ParagraphStyle("Callout", parent=styles["BodyText"], fontName="Helvetica-Bold",
                          fontSize=9.4, leading=13.4, textColor=NAVY, borderColor=CYAN,
                          borderWidth=0, leftIndent=8, rightIndent=8, spaceBefore=2, spaceAfter=2))
styles.add(ParagraphStyle("Formula", parent=styles["BodyText"], fontName="Courier-Bold",
                          fontSize=8.4, leading=12, textColor=NAVY, alignment=TA_CENTER,
                          backColor=PALE, borderPadding=7, spaceBefore=4, spaceAfter=7))
styles.add(ParagraphStyle("Foot", parent=styles["BodyText"], fontName="Helvetica-Oblique",
                          fontSize=7.2, leading=9.3, textColor=MUTED, spaceAfter=4))


def P(text, style="Bodyx"):
    return Paragraph(text, styles[style])


def table(data, widths, header=True, tiny=False, aligns=None):
    cooked = []
    for r, row in enumerate(data):
        if header and r == 0:
            header_style = ParagraphStyle(
                "TableHeaderLocal", parent=styles["Tiny" if tiny else "Small"],
                textColor=WHITE, fontName="Helvetica-Bold"
            )
            cooked.append([Paragraph(str(x), header_style) for x in row])
        else:
            cooked.append([P(str(x), "Tiny" if tiny else "Small") for x in row])
    t = Table(cooked, colWidths=widths, repeatRows=1 if header else 0, hAlign="LEFT")
    commands = [
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#CBD5E1")),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [WHITE, LIGHT]),
    ]
    if header:
        commands.extend([
            ("BACKGROUND", (0, 0), (-1, 0), NAVY),
            ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ])
    if aligns:
        for col, align in aligns.items():
            commands.append(("ALIGN", (col, 1 if header else 0), (col, -1), align))
    t.setStyle(TableStyle(commands))
    return t


def section(title, kicker=None):
    parts = []
    if kicker:
        parts.append(P(f"<font color='#18A0AE'><b>{kicker.upper()}</b></font>", "Small"))
    parts.append(P(title, "H1x"))
    parts.append(HRFlowable(width="100%", thickness=1.2, color=CYAN, spaceAfter=10))
    return parts


story = []

# Cover
cover = Table([
    [P("VEX COMPETITIVE<br/>RATING", "TitleBig")],
    [P("A strength-based ranking system for VEX V5 teams and events", "Subtitle")],
    [Spacer(1, 0.55 * inch)],
    [P("VCR combines opponent-adjusted match results, scoring contribution, defense, autonomous performance and expectation-adjusted event finishes. Awards are excluded.", "Subtitle")],
    [Spacer(1, 0.55 * inch)],
    [P("TEAM RATINGS  /  EVENT TIERS  /  EVENT WEIGHT", "Subtitle")],
], colWidths=[7.16 * inch], rowHeights=[1.05*inch, 0.55*inch, 0.65*inch, 1.12*inch, 0.65*inch, 0.45*inch])
cover.setStyle(TableStyle([
    ("BACKGROUND", (0, 0), (-1, -1), NAVY),
    ("BOX", (0, 0), (-1, -1), 0, NAVY),
    ("LEFTPADDING", (0, 0), (-1, -1), 28),
    ("RIGHTPADDING", (0, 0), (-1, -1), 28),
    ("TOPPADDING", (0, 0), (-1, -1), 15),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 15),
    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
]))
story += [Spacer(1, 0.45*inch), cover, Spacer(1, 0.25*inch),
          P("TECHNICAL SPECIFICATION  |  VERSION 1.0  |  AUGUST 2026", "Foot"), PageBreak()]

# Executive summary
story += section("1. System overview", "Purpose")
story += [P("The VEX Competitive Rating (VCR) estimates a team's current competitive strength. It is not a participation score and does not use judged awards. Every update asks one question: <b>did this team perform better or worse than a team of its rating was expected to perform?</b>"),
          P("A team begins near <b>1500</b>. Its rating changes after each match and event. Strong results against strong opposition matter more than routine wins against weak opposition. Event Weight adds a second layer: elite events offer greater upside, while poor performances by favorites at weak events carry greater downside."),
          P("Design principles", "H2x")]
principles = [
    ["Principle", "Rule"],
    ["Strength, not attendance", "Extra events cannot create rating points without above-expected performance."],
    ["Opponent-aware", "Results are evaluated against alliance and opponent strength."],
    ["Game-aware", "Statistics are normalized within the current game and event environment."],
    ["No awards", "Judged awards and skills unrelated to match competition are excluded."],
    ["Transparent", "Every rating change can be decomposed into matches, contribution, autonomous and finish."],
    ["Predictive", "Weights should be tuned by forecasting later matches, not by matching reputation."],
]
story += [table(principles, [1.55*inch, 5.55*inch]), Spacer(1, 8),
          P("Rating architecture", "H2x")]
architecture = [
    ["Layer", "Output", "Timing"],
    ["Match model", "Opponent-adjusted rating change", "After each official match"],
    ["Performance model", "OPR/DPR/CCWM and autonomous residuals", "After event data is complete"],
    ["Event model", "Tier, Event Weight and finish surprise", "Tier frozen before event; result after event"],
    ["Uncertainty model", "Update size and confidence", "Continuously"],
]
story += [table(architecture, [1.45*inch, 3.65*inch, 2.0*inch])]

story += [PageBreak()] + section("2. Competitive inputs", "Team model")
inputs = [
    ["Component", "Target share", "Measures"],
    ["Match performance", "40%", "Wins, ties, losses, margin and opponent strength"],
    ["Adjusted OPR", "20%", "Estimated scoring contribution"],
    ["Adjusted DPR", "10%", "Estimated points allowed or defensive impact"],
    ["CCWM", "10%", "Estimated net contribution to score margin"],
    ["Autonomous", "10%", "AWP rate and estimated autonomous contribution"],
    ["Event performance", "10%", "Qualification and elimination finish versus expectation"],
]
story += [table(inputs, [1.72*inch, 1.0*inch, 4.38*inch]),
          P("The shares are starting parameters, not permanent truths. Backtesting should optimize them for prediction accuracy while maintaining interpretability.", "Foot"),
          P("Avoiding double-counting", "H2x"),
          P("OPR, DPR and CCWM are mathematically related. In many implementations, <b>CCWM is approximately OPR minus DPR</b>. Adding all three at full strength would count the same signal more than once. Build a residualized contribution score instead:"),
          P("Contribution = 0.55 Z(OPR) + 0.20 Z(-DPR) + 0.25 Z(CCWM)", "Formula"),
          P("Z(x) = (x - event mean) / event standard deviation", "Formula"),
          P("If the data provider defines higher DPR as better defense, remove the negative sign. The project must document and preserve one convention.", "Foot"),
          P("Better long-term estimator", "H2x"),
          P("Estimate OPR-family values with ridge regression rather than unregularized least squares. Ridge regression reduces extreme estimates when teams play few matches or repeatedly share partners. Store standard errors so low-confidence statistics receive less influence."),
          P("Season and recency", "H2x"),
          P("Never compare raw scoring statistics across different games. Use current-season normalized values. Apply gradual recency decay to old evidence - for example, a 90-day half-life - while retaining rating uncertainty rather than resetting established teams abruptly.")]

story += [PageBreak()] + section("3. Match rating", "Opponent adjustment")
story += [P("For alliance AB against alliance CD, begin with the mean pre-match rating of each alliance:"),
          P("R(red) = (R(A) + R(B))/2     R(blue) = (R(C) + R(D))/2", "Formula"),
          P("E(red) = 1 / (1 + 10^((R(blue) - R(red))/400))", "Formula"),
          P("Actual score is 1.0 for a win, 0.5 for a tie and 0.0 for a loss. The unscaled surprise is Actual minus Expected."),
          P("Margin of victory", "H2x"),
          P("MOV = 1 + 0.35 tanh(ScoreMargin / EventScoreSD)", "Formula"),
          P("DeltaMatch = Kmatch x (Actual - Expected) x MOV", "Formula"),
          P("Start with <b>Kmatch = 20</b>. The bounded tanh function lets dominant performances matter without allowing a single blowout to overwhelm the model. Exclude disqualifications or score corrections only according to a documented data policy."),
          P("Sharing alliance credit", "H2x"),
          P("Allocate alliance change using predicted individual contribution, clamped so neither partner receives less than 35% or more than 65%:"),
          P("Share(i) = clamp(0.35, PredContribution(i) / SumAllianceContribution, 0.65)", "Formula"),
          P("When individual estimates are missing or unreliable, split the update 50/50. This avoids inventing precision."),
          P("Uncertainty", "H2x"),
          P("Maintain a rating deviation for every team. New, recently rebuilt, or inactive teams have greater uncertainty and therefore larger updates. Established teams have smaller, more stable changes. Publish both rating and confidence, but rank primarily by the conservative estimate:"),
          P("DisplayedStrength = Rating - 1.0 x RatingDeviation", "Formula")]

story += [PageBreak()] + section("4. Autonomous and event finish", "Performance adjustment")
story += [P("Autonomous performance should contain both outcome and contribution. Because AWP is earned by an alliance, compare the actual AWP outcome with its predicted probability rather than treating every AWP as equal."),
          P("AutoScore = 0.60 Z(Adjusted AWP Rate) + 0.40 Z(Auto Contribution)", "Formula"),
          P("Adjusted AWP Rate is the residual between observed AWP outcomes and probabilities predicted from all four participating teams. Auto Contribution may be estimated only when scoring breakdowns are reliable; otherwise use the AWP residual alone and lower confidence."),
          P("Event result percentile", "H2x"),
          P("ResultPercentile = 0.55 QualificationPercentile + 0.45 EliminationPercentile", "Formula")]
finish = [
    ["Elimination result", "Suggested percentile"],
    ["Champion", "1.00"], ["Finalist", "0.90"], ["Semifinalist", "0.75"],
    ["Quarterfinalist", "0.55"], ["Did not qualify", "Use qualification percentile"],
]
story += [table(finish, [3.55*inch, 3.55*inch]), Spacer(1, 7),
          P("Expected percentile is calculated from the team's frozen pre-event rating relative to the field. The model then measures surprise:"),
          P("EventSurprise = ResultPercentile - ExpectedPercentile", "Formula"),
          P("A favorite that finishes where expected receives little change. An underdog that reaches the final of an elite field receives a large positive surprise. Qualification percentile should use official ranking positions; elimination percentile should account for bracket size and byes."),
          P("Alliance selection caution", "H2x"),
          P("Elimination advancement is partly determined by alliance selection. Do not attribute an entire alliance finish equally. Combine finish surprise with match-level contribution and cap the finish component at 10% of the total event update.")]

story += [PageBreak()] + section("5. Event ranking", "Field quality")
story += [P("An event's tier is determined from the registered field's <b>frozen pre-event ratings</b>. Branding alone cannot make an event elite. Freezing the inputs prevents circular logic in which strong performances retroactively make their own event stronger."),
          P("Event Strength Score (ESS)", "H2x"),
          P("ESS = 0.35 FieldStrength + 0.30 FieldDepth + 0.15 EliteDensity + 0.10 RegionalDiversity + 0.10 FormatQuality", "Formula")]
ess = [
    ["Factor", "Weight", "Definition"],
    ["Field Strength", "35%", "Percentile rank of the field's mean pre-event rating"],
    ["Field Depth", "30%", "60% top-quarter strength + 40% top-half strength"],
    ["Elite Density", "15%", "Normalized density of global top 1%, 5% and 10% teams"],
    ["Regional Diversity", "10%", "Strong-team representation across regions/countries"],
    ["Format Quality", "10%", "Matches per team, field size, complete data and valid bracket"],
]
story += [table(ess, [1.45*inch, 0.8*inch, 4.85*inch]),
          P("Field Depth prevents one famous team from carrying an otherwise weak event. Regional Diversity distinguishes genuinely international fields without automatically penalizing a deep regional championship. Format Quality measures competitive reliability only; it does not include judged awards.", "Foot"),
          P("Eligibility rules", "H2x")]
elig = [
    ["Rule", "Recommended policy"],
    ["Minimum size", "24 teams for an official tier; smaller events remain provisional"],
    ["Data completeness", "At least 95% of official match results present"],
    ["Tier freeze", "Freeze 24 hours before the first scheduled match"],
    ["Late roster changes", "Recalculate only if more than 10% of teams change"],
    ["Regional ceiling", "Ordinary regional events may not exceed Bronze S"],
    ["Signature range", "Signature Events may be Bronze S, Silver S or Gold S"],
]
story += [table(elig, [2.0*inch, 5.1*inch])]

story += [PageBreak()] + section("6. Event tiers and Event Weight", "Tier system")
tiers = [
    ["Tier", "ESS", "Event Weight", "Typical classification"],
    ["C", "0-34", "0.70", "Small or weak local competition"],
    ["B", "35-49", "0.82", "Strong local / average regional competition"],
    ["A", "50-64", "0.95", "Strong regional competition"],
    ["Bronze S", "65-74", "1.15", "Regional championship / entry Signature"],
    ["Silver S", "75-87", "1.35", "Strong Signature Event"],
    ["Gold S", "88-100", "1.60", "Elite international Signature Event"],
    ["Worlds", "Special", "1.85", "VEX World Championship"],
]
story += [table(tiers, [1.15*inch, 0.8*inch, 1.15*inch, 4.0*inch]),
          P("If the public taxonomy must end at Gold S, display Worlds as Gold S with a championship modifier of 1.85.", "Foot"),
          P("Asymmetric Expectation Weight", "H2x"),
          P("A simple symmetric multiplier fails the design goal: lowering the weight of a C event would also reduce the penalty for a favorite that fails there. Use an asymmetric multiplier on event surprise:"),
          P("ContextWeight = EventWeight, if Surprise > 0;  1/EventWeight, if Surprise < 0", "Formula"),
          P("DeltaEvent = Kevent x EventSurprise x ContextWeight x Reliability", "Formula"),
          P("Start with <b>Kevent = 80</b> and cap the total event-level adjustment at <b>+/-80 rating points</b>. Reliability ranges from 0 to 1 and reflects match count, data completeness and statistical uncertainty."),
          P("Worked comparison", "H2x")]
examples = [
    ["Result", "C (0.70)", "Gold S (1.60)", "Interpretation"],
    ["+0.20 surprise", "+0.140 scaled", "+0.320 scaled", "Elite-event overperformance earns more"],
    ["-0.20 surprise", "-0.286 scaled", "-0.125 scaled", "Weak-event failure by a favorite hurts more"],
]
story += [table(examples, [1.4*inch, 1.25*inch, 1.35*inch, 3.1*inch], tiny=True)]

story += [PageBreak()] + section("7. Final update and safeguards", "Implementation")
story += [P("At event completion, combine the independently calculated components:"),
          P("DeltaVCR = 0.65 DeltaMatch + 0.20 DeltaContribution + 0.10 DeltaAuto + 0.05 DeltaFinish", "Formula"),
          P("The 65/20/10/5 blend is preferred over the conceptual 40/20/10/10/10 input shares for implementation because match results already absorb some scoring, defense and finish information. This more conservative blend reduces double-counting. Tune it through backtesting."),
          P("Required safeguards", "H2x")]
safeguards = [
    ["Control", "Purpose"],
    ["Chronological processing", "Never allow future results to grade an earlier event."],
    ["Frozen pre-event ratings", "Prevent circular event strength and expectation calculations."],
    ["Season normalization", "Never compare raw OPR-family values across different games."],
    ["Positive low-tier limit", "Only the best two positive C/B event bonuses count in a rolling 90-day window."],
    ["All negative results count", "Teams cannot hide weak performances through selective participation."],
    ["Event cap", "Limit event-level movement to +/-80 points."],
    ["Data-quality factor", "Reduce influence when schedules, scores or autonomous data are incomplete."],
    ["Public decomposition", "Show old rating, each component, Event Weight and new rating."],
]
story += [table(safeguards, [1.65*inch, 5.45*inch], tiny=True),
          P("Validation plan", "H2x"),
          P("Backtest chronologically across at least one complete season. Optimize for log loss, Brier score and calibration of predicted match probabilities. Compare VCR against win rate, plain Elo and OPR-only baselines. Validate separately by region, event tier and team experience. Publish major parameter changes and never tune on the same season used for final evaluation."),
          P("Recommended public display", "H2x")]
display = [
    ["Field", "Example"],
    ["World rank", "#12"], ["VCR", "1718"], ["Confidence", "+/-42"],
    ["Recent change", "+31"], ["Event tier", "Silver S (1.35)"],
    ["Reason", "+18 matches, +7 contribution, +4 auto, +2 finish"],
]
story += [table(display, [1.7*inch, 5.4*inch]), Spacer(1, 8),
          P("Status: initial specification. The constants in this document are defensible starting values; they should become data-calibrated parameters after historical VEX match data is available.", "Callout")]

doc = VCRDoc(str(OUT))
doc.build(story)
print(OUT)
