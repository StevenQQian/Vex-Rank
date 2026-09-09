from pathlib import Path
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, HRFlowable, KeepTogether

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "output" / "pdf" / "vex_competitive_rating_full_algorithm.pdf"
OUT.parent.mkdir(parents=True, exist_ok=True)

NAVY = colors.HexColor("#102A43")
BLUE = colors.HexColor("#1769AA")
TEAL = colors.HexColor("#0B9AA6")
INK = colors.HexColor("#243B53")
MUTED = colors.HexColor("#627D98")
PALE = colors.HexColor("#EAF4F8")
LIGHT = colors.HexColor("#F6F9FC")
WHITE = colors.white
AMBER = colors.HexColor("#D99A18")
RED = colors.HexColor("#B83232")


class SpecDoc(BaseDocTemplate):
    def __init__(self, filename):
        super().__init__(filename, pagesize=letter, leftMargin=.68*inch, rightMargin=.68*inch,
                         topMargin=.68*inch, bottomMargin=.62*inch,
                         title="VEX Competitive Rating - Full Algorithm Specification",
                         author="VEX V5 Ranking Project",
                         subject="Complete numerical specification for team, event, regional and alliance-selection rankings")
        frame = Frame(self.leftMargin, self.bottomMargin, self.width, self.height,
                      leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0, id="body")
        self.addPageTemplates(PageTemplate(id="spec", frames=[frame], onPage=self.decorate))

    def decorate(self, canvas, doc):
        p = canvas.getPageNumber()
        if p == 1:
            return
        xl, xr = .68*inch, letter[0]-.68*inch
        canvas.saveState()
        canvas.setStrokeColor(colors.HexColor("#D9E2EC")); canvas.setLineWidth(.5)
        canvas.line(xl, letter[1]-.42*inch, xr, letter[1]-.42*inch)
        canvas.setFont("Helvetica-Bold", 8); canvas.setFillColor(BLUE)
        canvas.drawString(xl, letter[1]-.30*inch, "VEX COMPETITIVE RATING - FULL SPECIFICATION")
        canvas.setFont("Helvetica", 8); canvas.setFillColor(MUTED)
        canvas.drawString(xl, .34*inch, "Version 2.0 | September 2026")
        canvas.drawRightString(xr, .34*inch, f"PAGE {p}")
        canvas.restoreState()


S = getSampleStyleSheet()
S.add(ParagraphStyle("CoverTitle", parent=S["Title"], fontName="Helvetica-Bold", fontSize=28,
                     leading=31, textColor=WHITE, alignment=0, spaceAfter=12))
S.add(ParagraphStyle("CoverSub", parent=S["Normal"], fontName="Helvetica", fontSize=12.5,
                     leading=17.5, textColor=colors.HexColor("#D9F0F2")))
S.add(ParagraphStyle("H1x", parent=S["Heading1"], fontName="Helvetica-Bold", fontSize=17.5,
                     leading=21, textColor=NAVY, spaceBefore=3, spaceAfter=8))
S.add(ParagraphStyle("H2x", parent=S["Heading2"], fontName="Helvetica-Bold", fontSize=11.7,
                     leading=14.5, textColor=BLUE, spaceBefore=8, spaceAfter=4))
S.add(ParagraphStyle("H3x", parent=S["Heading3"], fontName="Helvetica-Bold", fontSize=9.5,
                     leading=12, textColor=TEAL, spaceBefore=6, spaceAfter=3))
S.add(ParagraphStyle("Bodyx", parent=S["BodyText"], fontName="Helvetica", fontSize=8.8,
                     leading=12.5, textColor=INK, spaceAfter=5.5))
S.add(ParagraphStyle("Small", parent=S["BodyText"], fontName="Helvetica", fontSize=7.35,
                     leading=9.6, textColor=INK))
S.add(ParagraphStyle("Tiny", parent=S["BodyText"], fontName="Helvetica", fontSize=6.5,
                     leading=8.2, textColor=INK))
S.add(ParagraphStyle("Formula", parent=S["BodyText"], fontName="Courier-Bold", fontSize=7.65,
                     leading=10.6, textColor=NAVY, alignment=TA_CENTER, backColor=PALE,
                     borderPadding=6, spaceBefore=3, spaceAfter=6))
S.add(ParagraphStyle("Note", parent=S["BodyText"], fontName="Helvetica-Oblique", fontSize=7.2,
                     leading=9.5, textColor=MUTED, leftIndent=5, rightIndent=5, spaceAfter=5))
S.add(ParagraphStyle("Callout", parent=S["BodyText"], fontName="Helvetica-Bold", fontSize=8.5,
                     leading=12, textColor=NAVY, backColor=colors.HexColor("#FFF7E6"),
                     borderColor=AMBER, borderWidth=.6, borderPadding=7, spaceBefore=4, spaceAfter=7))


def P(text, style="Bodyx"):
    return Paragraph(text, S[style])


def T(rows, widths, tiny=False, repeat=True, aligns=None):
    body_style = S["Tiny" if tiny else "Small"]
    head_style = ParagraphStyle("headlocal", parent=body_style, textColor=WHITE, fontName="Helvetica-Bold")
    cooked = []
    for i, row in enumerate(rows):
        st = head_style if i == 0 else body_style
        cooked.append([Paragraph(str(v), st) for v in row])
    tab = Table(cooked, colWidths=widths, repeatRows=1 if repeat else 0, hAlign="LEFT")
    cmds = [
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"), ("GRID", (0,0), (-1,-1), .35, colors.HexColor("#CBD5E1")),
        ("BACKGROUND", (0,0), (-1,0), NAVY), ("TEXTCOLOR", (0,0), (-1,0), WHITE),
        ("ROWBACKGROUNDS", (0,1), (-1,-1), [WHITE, LIGHT]),
        ("LEFTPADDING", (0,0), (-1,-1), 4.5), ("RIGHTPADDING", (0,0), (-1,-1), 4.5),
        ("TOPPADDING", (0,0), (-1,-1), 3.6), ("BOTTOMPADDING", (0,0), (-1,-1), 3.6),
    ]
    if aligns:
        for col, align in aligns.items(): cmds.append(("ALIGN", (col,1), (col,-1), align))
    tab.setStyle(TableStyle(cmds))
    return tab


def section(num, title, kicker):
    return [P(f"<font color='#0B9AA6'><b>{kicker.upper()}</b></font>", "Small"),
            P(f"{num}. {title}", "H1x"),
            HRFlowable(width="100%", thickness=1.1, color=TEAL, spaceAfter=8)]


def bullets(items):
    return [P("&#8226; " + x) for x in items]


story = []

# Cover
cover = Table([
    [P("VEX COMPETITIVE<br/>RATING", "CoverTitle")],
    [P("Full algorithm documentation", "CoverSub")],
    [Spacer(1, .52*inch)],
    [P("A complete numerical specification for ranking VEX V5 teams, events, regions, offensive and defensive strength, elimination performance, alliance contribution, and alliance-selection decision quality.", "CoverSub")],
    [Spacer(1, .45*inch)],
    [P("DEFINITIVE LAUNCH MODEL  /  VERSION 2.0", "CoverSub")],
], colWidths=[7.16*inch], rowHeights=[1.0*inch,.42*inch,.58*inch,1.12*inch,.55*inch,.42*inch])
cover.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,-1),NAVY), ("LEFTPADDING",(0,0),(-1,-1),28),
                           ("RIGHTPADDING",(0,0),(-1,-1),28), ("TOPPADDING",(0,0),(-1,-1),14),
                           ("BOTTOMPADDING",(0,0),(-1,-1),14), ("VALIGN",(0,0),(-1,-1),"MIDDLE")]))
story += [Spacer(1,.42*inch), cover, Spacer(1,.22*inch), P("Prepared for the VEX V5 global ranking and statistics platform | September 2026", "Note"), PageBreak()]

# 1
story += section("1", "Purpose and model philosophy", "System definition")
story += [P("VEX Competitive Rating (VCR) estimates current competitive strength. It rewards performance above expectation, not attendance, raw score accumulation, geography, awards, or reputation. Every public change must be reproducible from frozen pre-event information and official results."),
          P("Primary outputs", "H2x")]
story += [T([["Output","Scale","Meaning"],
             ["Internal rating mu","Centered at 1500","Elo-style latent team strength"],
             ["Public VCR","0-1000","Readable transformation of conservative strength"],
             ["Rating deviation RD","40-350","Uncertainty; lower is more certain"],
             ["Event Strength Score ESS","0-100","Field quality and competitive reliability"],
             ["Event tier","C to Gold S / Worlds","Public event classification"],
             ["Offense / Defense","Game-point units","Globally adjusted contribution estimates"],
             ["ASE","0-100","Alliance Selection Efficiency; separate from VCR"]],
            [1.65*inch,1.35*inch,4.1*inch])]
story += [P("Non-negotiable rules", "H2x")]
story += bullets([
    "Judged awards never enter VCR, ESS, offense, defense, elimination, or regional-strength calculations.",
    "Raw OPR is never compared across different games and is never used alone for a global leaderboard.",
    "Event tier and team expectations are frozen before an event begins; future evidence cannot alter an earlier expectation.",
    "Country is never a permanent handicap. Weak or isolated evidence receives lower confidence until cross-region performance verifies it.",
    "All negative eligible results count. Positive-event limits prevent participation volume from becoming a ranking strategy.",
])
story += [P("Launch status", "H2x"), P("All constants marked <b>launch default</b> are initial values. They remain fixed for a published season unless a documented emergency correction is required. Future values are selected by chronological backtesting, not by manually matching popular opinion.", "Callout")]

# 2
story += [PageBreak()] + section("2", "Data model and eligibility", "Required inputs")
story += [P("The processor consumes official events, teams, matches, alliance assignments, scores, rankings, elimination brackets, autonomous outcomes, invitation/decline records when available, and geographical metadata."),
          P("Match eligibility", "H2x")]
story += [T([["Condition","Treatment"],
             ["Official scored match","Full weight"],
             ["Tie","Actual result = 0.5"],
             ["Team disqualification","Score result counts; reliability may be 0.75 if data cannot separate cause"],
             ["No-show / disabled entire match","Result counts; MOV capped at 1.10; contribution reliability = 0.25"],
             ["Replay supersedes original","Use final official replay only"],
             ["Practice / skills / scrimmage","Excluded"],
             ["Missing score","Excluded from score models; W/T/L may count at reliability 0.50"],
             ["Correction after publication","Reprocess event and all later events chronologically"]],
            [2.05*inch,5.05*inch], tiny=True)]
story += [P("Event eligibility", "H2x")]
story += [T([["Parameter","Launch default"],
             ["Official tier minimum field","24 teams"],
             ["Minimum official data completeness","95% of match outcomes"],
             ["Tier freeze","24 hours before scheduled first match"],
             ["Tier roster recalculation trigger","More than 10% of registered teams change after freeze"],
             ["Provisional event","Fewer than 24 teams or below 95% completeness"],
             ["Provisional event rating influence","Reliability capped at 0.70"],
             ["Minimum offense leaderboard sample","12 valid matches and 2 events"],
             ["Active-team window","At least one event in last 150 days"]],
            [2.45*inch,4.65*inch])]
story += [P("Canonical processing order", "H2x")]
story += bullets(["Freeze entrant ratings and event tier.", "Process official matches in chronological order.", "Fit event contribution statistics after results are complete.", "Calculate qualification and elimination outcomes versus frozen expectations.", "Apply one event-close adjustment.", "Update uncertainty, recency evidence, regional links, and leaderboards."])

# 3
story += [PageBreak()] + section("3", "Rating state, initialization, and display", "Core state")
story += [P("Each team-season stores latent rating mu, rating deviation RD, match count, event count, last-active date, and four component histories. Internal values use the Elo center; the site displays a bounded public scale."),
          P("Initialization", "H2x")]
story += [T([["Team state","mu","RD"],
             ["Completely new team","1500","350"],
             ["Returning team after seasonal carryover","Formula below","Maximum 220"],
             ["Established active team floor","Current","Minimum 40"]], [2.55*inch,1.55*inch,3.0*inch])]
story += [P("SeasonStartMu = 1500 + 0.40 x (PreviousSeasonEndMu - 1500)", "Formula"),
          P("SeasonStartRD = min(220, sqrt(PreviousRD^2 + 120^2))", "Formula"),
          P("The 40% carryover recognizes persistent program quality while allowing a new game, robot, roster, and strategy to redefine strength."),
          P("Conservative strength and public VCR", "H2x"),
          P("ConservativeMu = mu - 0.75 x RD", "Formula"),
          P("PublicVCR = clamp(0, 1000, 500 + 1.25 x (ConservativeMu - 1500))", "Formula"),
          P("Example: mu 1700 and RD 60 gives ConservativeMu 1655 and PublicVCR 693.75, displayed as <b>694</b>. Global ordering uses unrounded ConservativeMu, so displayed ties remain deterministic."),
          P("Tie-break sequence", "H2x")]
story += [T([["Order","Tie-break"],["1","Higher unrounded ConservativeMu"],["2","Lower RD"],["3","Higher last-90-day event evidence"],["4","Higher elimination component"],["5","Team number ascending"]], [1.0*inch,6.1*inch])]

# 4
story += [PageBreak()] + section("4", "Opponent-adjusted match model", "Match engine")
story += [P("For red alliance A+B against blue alliance C+D:"),
          P("Rred = (muA + muB)/2     Rblue = (muC + muD)/2", "Formula"),
          P("Ered = 1 / (1 + 10^((Rblue - Rred)/400))     Eblue = 1 - Ered", "Formula"),
          P("Actual is 1.0 for a win, 0.5 for a tie, and 0.0 for a loss. Base surprise equals Actual minus Expected."),
          P("Margin of victory", "H2x"),
          P("MOV = 1 + 0.35 x tanh(ScoreMargin / max(EventScoreSD, 12))", "Formula"),
          P("Launch Kmatch = 20. Qualification MOV is capped at 1.30; elimination MOV at 1.20 because advancement is separately rewarded. A no-show match is capped at 1.10."),
          P("AllianceDelta = Kmatch x (Actual - Expected) x MOV x MatchReliability", "Formula")]
story += [T([["Match reliability condition","Value"],
             ["Normal complete official match","1.00"], ["Partial scoring detail but valid outcome","0.85"],
             ["DQ with ambiguous individual cause","0.75"], ["Outcome only / missing score","0.50"],
             ["Major no-show or disabled-data ambiguity","0.25 for contribution; 1.00 for W/T/L"]], [3.1*inch,4.0*inch])]
story += [P("Do not multiply ordinary match updates by Event Weight. The field's ratings already set match difficulty. Event Weight is applied to event-close evidence and elimination surprise, preventing double-counting of opponent strength.", "Callout")]

# 5
story += [PageBreak()] + section("5", "Dynamic alliance contribution sharing", "Credit allocation")
story += [P("The fixed 35/65 split is replaced by a dynamic 20/80 range. Current-event evidence outweighs global rating once enough matches exist. A team is never granted credit solely because it was already highly ranked."),
          P("Evidence weights by matches completed before the evaluated match", "H2x")]
story += [T([["Prior valid matches","Global VCR","Event performance","Event rank"],
             ["0-1","60%","35%","5%"], ["2-3","40%","50%","10%"],
             ["4-5","30%","56%","14%"], ["6+","20%","60%","20%"]],
            [1.85*inch,1.55*inch,1.85*inch,1.85*inch])]
story += [P("Global confidence multiplier", "H2x")]
story += [T([["Prior event history","Global confidence"], ["0 events","0.10"], ["1 event","0.35"],
             ["2 events","0.60"], ["3+ recent events","1.00"]], [3.4*inch,3.7*inch])]
story += [P("Multiply the global weight by confidence and transfer unused weight proportionally to Event Performance and Event Rank. Standardize all three inputs before combination."),
          P("LocalStrength_i = wg Z(Global_i) + wp Z(EventPerformance_i) + wr Z(EventRank_i)", "Formula"),
          P("RawShareA = exp(LocalStrengthA/1.5) / [exp(LocalStrengthA/1.5) + exp(LocalStrengthB/1.5)]", "Formula"),
          P("ShareA = clamp(DynamicMin, RawShareA, DynamicMax); ShareB = 1 - ShareA", "Formula")]
story += [T([["Absolute partner VCR gap","Stronger-team maximum","Weaker-team minimum"],
             ["0-99","0.55","0.45"], ["100-199","0.65","0.35"],
             ["200-299","0.725","0.275"], ["300+","0.80","0.20"]], [2.35*inch,2.4*inch,2.35*inch])]
story += [P("For match N, use event evidence from matches 1 through N-1. At event close, a leave-one-match-out recalculation may evaluate each match using every other match, preventing a match from justifying its own credit allocation."),
          P("Loss responsibility", "H2x"),
          P("LossShare_i = 0.50 x ExpectedContributionShare_i + 0.50 x UnderperformanceShare_i", "Formula"),
          P("This prevents a strong team from assigning every loss to a weaker partner. Underperformance is the positive magnitude of the team's contribution residual below expectation, normalized across both partners.")]

# 6
story += [PageBreak()] + section("6", "Global offense, defense, OPR, DPR, and CCWM", "Contribution model")
story += [P("Raw event OPR is descriptive, not a global strength measure. Global estimates must adjust for partners, opponent defense, event environment, limited schedules, and disconnected regions."),
          P("Regularized score model", "H2x"),
          P("AllianceScore = GameBaseline + OffA + OffB - DefC - DefD + EventEnvironment + Error", "Formula"),
          P("Fit offense and defense with ridge regression. Standardize design-matrix columns. Launch ridge penalty lambda = 8.0, selected later by five-fold event-grouped cross-validation over {1, 2, 4, 8, 16, 32}. Never split matches from the same event across training and validation folds."),
          P("Derived values", "H2x")]
story += [T([["Metric","Definition","Public direction"],
             ["Adjusted OPR","Estimated offensive point contribution","Higher is better"],
             ["Adjusted DPR","Estimated points prevented","Higher is better in VCR storage"],
             ["CCWM","Adjusted OPR + Adjusted DPR","Higher is better"],
             ["Offense conservative score","Adjusted OPR - 1.0 x SE(OPR)","Higher is better"],
             ["Defense conservative score","Adjusted DPR - 1.0 x SE(DPR)","Higher is better"]], [1.75*inch,3.35*inch,2.0*inch], tiny=True)]
story += [P("Because conventional DPR definitions sometimes use points allowed, ingestion must convert them to the internal 'points prevented' direction once. Never negate the value again downstream."),
          P("Contribution composite", "H2x"),
          P("ContributionZ = 0.55 Z(AdjOPR) + 0.20 Z(AdjDPR) + 0.25 Z(CCWM_residual)", "Formula"),
          P("CCWM_residual is the portion of CCWM not already explained by adjusted OPR and DPR. Residualization prevents the identity CCWM approximately equals OPR minus conventional DPR from being counted repeatedly."),
          P("Event performance used for partner sharing", "H2x"),
          P("EventPerformance = 0.45 Z(AdjOPR) + 0.20 Z(AdjDPR) + 0.20 Z(CCWM_residual) + 0.15 Z(Auto)", "Formula")]

# 7
story += [PageBreak()] + section("7", "Autonomous performance", "Game-phase model")
story += [P("Autonomous is treated as both an alliance outcome and an estimated individual contribution. The Autonomous Win Point (AWP) is never credited equally without adjustment because partners and opponents affect the probability."),
          P("PAWP = logistic(b0 + AutoA + AutoB - AutoC - AutoD)", "Formula"),
          P("AWPResidual = ActualAWP - PAWP", "Formula"),
          P("AutoScore = 0.60 Z(AWPResidualRate) + 0.40 Z(AutoContribution)", "Formula"),
          P("If individual autonomous scoring detail is unavailable, set AutoScore = Z(AWPResidualRate), reduce AutoReliability to 0.65, and redistribute the missing 40% internally rather than treating it as zero."),
          P("Autonomous constants", "H2x")]
story += [T([["Parameter","Launch default"], ["Minimum AWP sample for display","6 eligible qualification matches"],
             ["AWP logistic ridge penalty","8.0"], ["Auto contribution weight when detailed data exists","40%"],
             ["AWP residual weight","60%"], ["Missing-detail reliability","0.65"],
             ["Autonomous share of event-close VCR update","10%"]], [3.65*inch,3.45*inch])]
story += [P("Game-specific rule configuration", "H2x"), P("The definition of eligible autonomous outcomes, ties, bonus completion, and point attribution belongs in a season rules file. Algorithm code must not hard-code one year's field elements. When a season has no AWP, replace AWPResidualRate with autonomous-period win probability residual.")]

# 8
story += [PageBreak()] + section("8", "Qualification and elimination performance", "Tournament outcomes")
story += [P("Tournament advancement is materially important. Event Result receives 17% of the event-close update, and elimination receives 65% of Event Result. Expected performance prevents a famous team from gaining simply for meeting expectations."),
          P("ResultPercentile = 0.35 x QualificationPercentile + 0.65 x EliminationPercentile", "Formula"),
          P("EventSurprise = ResultPercentile - ExpectedResultPercentile", "Formula")]
story += [T([["Outcome","Elimination percentile"], ["Champion","1.00"], ["Finalist","0.92"],
             ["Semifinalist","0.82"], ["Quarterfinalist","0.70"], ["Round of 16","0.55"],
             ["First elimination round","0.40"], ["Qualified but not selected","0.25"],
             ["Did not qualify","0.05 + 0.15 x QualificationPercentile"]], [3.6*inch,3.5*inch])]
story += [P("For bracket formats with different rounds, map advancement continuously: losing-round percentile = 0.25 + 0.65 x fraction of elimination rounds survived, capped below finalist. Published event adapters must document the mapping."),
          P("Elimination importance", "H2x")]
story += [T([["Tier","Elimination modifier","Elimination component cap"], ["C","0.85","+/-25"],
             ["B","0.90","+/-25"], ["A","1.00","+/-35"], ["Bronze S","1.10","+/-35"],
             ["Silver S","1.20","+/-45"], ["Gold S","1.30","+/-45"], ["Worlds","1.45","+/-60"]],
            [1.5*inch,2.6*inch,3.0*inch])]
story += [P("DeltaElim = clamp(cap, 55 x EliminationSurprise x EventWeight x EliminationModifier)", "Formula"),
          P("A team expected at 0.72 that records 0.15 at Worlds has surprise -0.57. Raw change is approximately -84 and is capped at -60. Missing eliminations therefore matters, but cannot erase an exceptional season in one step."),
          P("Alliance-selection protection", "H2x"), P("A strong unselected team is not treated identically to a team that performs poorly in eliminations. Qualification percentile, contribution residuals, selection status, DQs, substitutions, and reliability soften or redistribute the outcome. The bracket result remains real evidence, not an absolute measure of one robot.")]

# 9
story += [PageBreak()] + section("9", "Event Strength Score and tiers", "Event ranking")
story += [P("ESS uses frozen pre-event team information. Event branding sets eligibility ceilings, not automatic status."),
          P("ESS = 0.30 FieldStrength + 0.25 FieldDepth + 0.15 EliteDensity + 0.15 RegionalCalibration + 0.10 FormatQuality + 0.05 RegionalDiversity", "Formula")]
story += [T([["Component","Weight","Exact launch definition"],
             ["Field Strength","30%","Percentile of trimmed mean entrant ConservativeMu; trim top/bottom 5%"],
             ["Field Depth","25%","60% top-quarter mean percentile + 40% top-half mean percentile"],
             ["Elite Density","15%","50% top-1% density + 30% top-5% + 20% top-10%, percentile normalized"],
             ["Regional Calibration","15%","Entrant-weighted Regional Strength Index"],
             ["Format Quality","10%","See numerical table below"],
             ["Regional Diversity","5%","Effective-region diversity normalized against same event class"]],
            [1.45*inch,.75*inch,4.9*inch], tiny=True)]
story += [P("Format Quality = 0.35 MatchCount + 0.25 FieldSize + 0.25 DataCompleteness + 0.15 BracketIntegrity", "Formula")]
story += [T([["Subscore","0 points","50 points","100 points"],
             ["Qualification matches/team","4 or fewer","6","8 or more"],
             ["Field size","12 or fewer","24","48 or more"],
             ["Data completeness","Below 80%","90%","100%"],
             ["Bracket integrity","Invalid/missing","Reduced bracket","Complete standard bracket"]],
            [1.9*inch,1.7*inch,1.7*inch,1.8*inch], tiny=True)]
story += [P("Interpolate linearly between anchors and clamp each subscore to 0-100."), P("Tier thresholds", "H2x")]
story += [T([["Tier","ESS","Event Weight","Eligibility / typical event"], ["C","0-34","0.70","Any official local event"],
             ["B","35-49","0.82","Strong local / average regional"], ["A","50-64","0.95","Strong regional competition"],
             ["Bronze S","65-74","1.15","Regional championship or Signature"],
             ["Silver S","75-87","1.35","Signature only"], ["Gold S","88-100","1.60","Signature only"],
             ["Worlds","Special","1.85","Official World Championship"]], [1.1*inch,.8*inch,1.15*inch,4.05*inch], tiny=True)]
story += [P("Ordinary regional events cannot exceed Bronze S. Regional championships can reach Bronze S. Signature Events can be Bronze, Silver, or Gold S; a Signature label does not guarantee strength.")]

# 10
story += [PageBreak()] + section("10", "Event Weight and asymmetric expectation", "Upside and downside")
story += [P("Event Weight changes the value of event-close surprise. High-tier overperformance earns more; a favorite failing at a weak event is punished more. This requires an asymmetric rule."),
          P("ContextWeight = EventWeight when Surprise >= 0; 1/EventWeight when Surprise < 0", "Formula"),
          P("DeltaEventBase = 80 x EventSurprise x ContextWeight x EventReliability", "Formula"),
          P("DeltaEventBase is capped at +/-80 before component blending. Elimination uses its separate formula and cap from Section 8."),
          P("Worked values before K and reliability", "H2x")]
story += [T([["Surprise","C 0.70","A 0.95","Bronze S 1.15","Silver S 1.35","Gold S 1.60"],
             ["+0.20","+0.140","+0.190","+0.230","+0.270","+0.320"],
             ["-0.20","-0.286","-0.211","-0.174","-0.148","-0.125"]],
            [1.0*inch,1.1*inch,1.1*inch,1.3*inch,1.3*inch,1.3*inch], tiny=True)]
story += [P("Event reliability", "H2x"),
          P("EventReliability = 0.40 DataCompleteness + 0.30 MatchSample + 0.20 ModelConnectivity + 0.10 BracketIntegrity", "Formula")]
story += [T([["Input","Launch mapping"], ["DataCompleteness","Observed valid matches / expected matches"],
             ["MatchSample","min(1, average valid matches per team / 8)"],
             ["ModelConnectivity","min(1, connected cross-event opponents / 12), floor 0.50"],
             ["BracketIntegrity","1.00 complete; 0.75 reduced; 0.50 missing"]], [2.0*inch,5.1*inch])]
story += [P("Event Weight never excuses weak match results. It controls how much a tournament-level result changes confidence in a team relative to the field.", "Callout")]

# 11
story += [PageBreak()] + section("11", "Regional ranking and calibration", "Global fairness")
story += [P("Each team is shown in global, continental, country/region, global offense, and regional offense tables. Regional tables filter the same underlying global model; they do not create inflated parallel ratings."),
          P("Regional Strength Index", "H2x"),
          P("RSI = 0.35 CrossRegionResults + 0.25 TopTeamStrength + 0.20 RegionalDepth + 0.10 InternationalParticipation + 0.10 DataReliability", "Formula")]
story += [T([["Factor","Exact definition"],
             ["CrossRegionResults","Percentile of exponentially weighted Actual-minus-Expected result in cross-region matches"],
             ["TopTeamStrength","Trimmed mean ConservativeMu of top 10-20% active teams; minimum 5 teams"],
             ["RegionalDepth","50% regional median + 50% upper-half mean, percentile normalized"],
             ["InternationalParticipation","Effective number of cross-region opponents, saturating at 40"],
             ["DataReliability","min(1, valid regional matches/300) x min(1, cross-region links/40)"]], [2.05*inch,5.05*inch], tiny=True)]
story += [T([["RSI state","Regional factor","Use"], ["Unknown / isolated","0.85","High uncertainty; not a country penalty"],
             ["0-34","0.80-0.90","Weak evidence environment"], ["35-49","0.90-0.97","Below average"],
             ["50-64","0.97-1.03","Average"], ["65-79","1.03-1.08","Strong"],
             ["80-100","1.08-1.12","Elite/deep"]], [2.1*inch,1.65*inch,3.35*inch])]
story += [P("The factor is used inside RegionalCalibration in ESS; do not multiply it onto Event Weight again."),
          P("Isolated-region shrinkage", "H2x"),
          P("RegionalConfidence = CrossRegionEvidence / (CrossRegionEvidence + 12)", "Formula"),
          P("CalibratedMetric = Confidence x Estimate + (1 - Confidence) x GlobalMean", "Formula")]
story += [T([["Cross-region evidence","Confidence"], ["0","0%"], ["3","20%"], ["6","33%"],
             ["12","50%"], ["24","67%"], ["48","80%"]], [3.55*inch,3.55*inch])]
story += [P("Repeated local opposition", "H2x"), P("NoveltyWeight = 1 / sqrt(1 + RepeatedOpponentCount)", "Formula"),
          P("This weight affects new evidence and uncertainty reduction, not whether the result counts. First exposure is 100%, second 71%, fourth 50%, ninth 33%, and sixteenth 25%.")]

# 12
story += [PageBreak()] + section("12", "Season phases, recency, and inactivity", "One-year season")
story += [P("Past evidence decays; the underlying rating is not automatically destroyed. This avoids inactivity punishment while ensuring one early Signature victory cannot control the late-season leaderboard."),
          P("RecencyWeight(days) = 2^(-days/75)", "Formula")]
story += [T([["Age","Remaining influence"], ["0 days","100%"], ["30 days","75.8%"], ["75 days","50%"],
             ["150 days","25%"], ["225 days","12.5%"], ["300 days","6.25%"], ["365 days","3.4%"]], [3.55*inch,3.55*inch])]
story += [P("Season phases", "H2x")]
story += [T([["Phase","Calendar portion","Current-season evidence","Starting prior"],
             ["Early","First 30%","60%","40%"], ["Mid","Next 35%","80%","20%"],
             ["Late","Final 35%","95%","5%"]], [1.35*inch,1.9*inch,2.0*inch,1.85*inch])]
story += [P("EvidenceWeight_i = EventWeight_i x RecencyWeight_i x Reliability_i", "Formula"),
          P("RecentPerformance = sum(EvidenceWeight_i x Performance_i) / sum(EvidenceWeight_i)", "Formula"),
          P("Single-event dominance controls", "H2x")]
story += [T([["Control","Launch default"], ["Maximum one-event share of positive evidence","30% after team has 3+ events"],
             ["Confirmation multiplier: only one positive event","0.75"], ["Two consistent events","0.90"],
             ["Three or more consistent events","1.00"], ["Low-tier positive-event count","Best 2 C/B bonuses in rolling 90 days"],
             ["Negative events","All count"]], [3.15*inch,3.95*inch])]
story += [P("Inactivity", "H2x"),
          P("After a 30-day grace period: RDnew = min(350, RDold + 0.20 x InactiveDaysBeyondGrace)", "Formula"),
          P("This lowers conservative rank through uncertainty without claiming the team definitely became worse.")]

# 13
story += [PageBreak()] + section("13", "Alliance Selection Efficiency", "Decision quality")
story += [P("ASE is a separate 0-100 profile metric. It measures whether an alliance captain selected a strong available partner using information available at selection time. ASE never enters VCR."),
          P("PickValue = 0.35 AllianceStrength + 0.20 AutoCompatibility + 0.15 StrategicCompatibility + 0.15 Reliability + 0.10 ScheduleAdjustedPerformance + 0.05 SelectionFlexibility", "Formula"),
          P("OptimalValue = max PickValue among genuinely available teams", "Formula"),
          P("PickRegret = OptimalValue - SelectedPickValue", "Formula"),
          P("PickEfficiency = clamp(0, 100, 100 x [1 - PickRegret/MaximumReasonableRegret])", "Formula")]
story += [T([["ASE","Interpretation"], ["90-100","Near-optimal selector"], ["75-89","Strong selector"],
             ["60-74","Generally reasonable"], ["40-59","Questionable / average uncertainty"], ["0-39","Repeatedly poor choices"]], [2.0*inch,5.1*inch])]
story += [P("Selection weights", "H2x")]
story += [T([["Decision","Importance"], ["First partner","1.00"], ["Second partner","0.70"],
             ["Third / substitute","0.40"]], [3.55*inch,3.55*inch])]
story += [P("HistoricalASE = sum(Recency x EventWeight x Importance x Efficiency) / sum(weights)", "Formula"),
          P("PublishedASE = [n/(n+5)] x ObservedASE + [5/(n+5)] x 50", "Formula"),
          P("Previous-season carryover: StartingASE = 50 + 0.40 x (PreviousASE - 50)", "Formula"),
          P("Reconstruct prior selections, declines, captain availability, pick order, and event rules. Never penalize a team for not selecting an unavailable or declining team. If compatibility data is missing, show low confidence and rely on projected alliance strength.")]

# 14
story += [PageBreak()] + section("14", "Complete event-close update", "Final team calculation")
story += [P("After all event models are available, calculate four non-overlapping component deltas. The launch blend gives elimination and tournament outcome materially more influence than the original prototype."),
          P("DeltaVCR_internal = 0.55 DeltaMatch + 0.18 DeltaContribution + 0.10 DeltaAuto + 0.17 DeltaEventResult", "Formula")]
story += [T([["Component","Weight","Component range before blend"], ["Match","55%","Natural match sum; event-normalized and capped +/-100"],
             ["Contribution","18%","+/-80"], ["Autonomous","10%","+/-60"],
             ["Event Result","17%","+/-80; elimination subcomponent has tier caps"]], [2.1*inch,1.15*inch,3.85*inch])]
story += [P("FinalEventDelta = clamp(-100, +100, DeltaVCR_internal)", "Formula"),
          P("mu_after = mu_before + FinalEventDelta", "Formula"),
          P("RD reduction", "H2x"),
          P("EffectiveMatches = sum(MatchReliability x NoveltyWeight)", "Formula"),
          P("RD_after = max(40, RD_before / sqrt(1 + EffectiveMatches/6))", "Formula"),
          P("An established team therefore stabilizes gradually; a new team can move quickly but remains conservatively ranked until evidence accumulates."),
          P("Double-counting controls", "H2x")]
story += bullets([
    "Match outcomes carry most weight; contribution uses residualized statistics.",
    "Qualification and elimination MOV caps are lower because advancement is separately modeled.",
    "Event Weight does not multiply ordinary Elo match updates.",
    "Regional calibration is inside ESS and is never applied a second time.",
    "CCWM is residualized after adjusted offense and defense.",
])

# 15
story += [PageBreak()] + section("15", "Worked end-to-end example", "Numerical walkthrough")
story += [P("Team X enters a Silver S event at mu 1710, RD 70. Its conservative strength is 1657.5, giving public VCR 697. The event has ESS 81, Event Weight 1.35, and reliability 0.94."),
          P("Match evidence", "H2x"),
          P("Across eight matches, opponent-adjusted alliance deltas allocated through dynamic partner shares sum to +34. MOV and reliability are already included. DeltaMatch = +34."),
          P("Contribution and autonomous", "H2x"),
          P("Adjusted OPR, defense, and residual CCWM produce ContributionZ +0.80, mapped to DeltaContribution +28. AutoScore +0.45 maps to DeltaAuto +14."),
          P("Tournament result", "H2x"),
          P("Qualification percentile = 0.78. The team reaches semifinals, elimination percentile 0.82. ResultPercentile = 0.35(0.78) + 0.65(0.82) = 0.806. Frozen expected percentile was 0.65, so EventSurprise = +0.156."),
          P("Base event surprise = 80 x 0.156 x 1.35 x 0.94 = +15.84", "Formula"),
          P("Elimination surprise subcomponent remains within the Silver S +/-45 cap. The combined Event Result delta is +22 after qualification/elimination decomposition."),
          P("Final blend", "H2x"),
          P("Delta = 0.55(34) + 0.18(28) + 0.10(14) + 0.17(22) = 28.88", "Formula"),
          P("Round internal event delta to four decimals, not an integer. New mu = 1738.88. If RD falls from 70 to 48, ConservativeMu = 1702.88 and public VCR = 754 after rounding."),
          P("Interpretation", "H2x"),
          P("The team improves because it beat expectations across matches, contribution, autonomous, and advancement. Its public VCR rises more than mu alone suggests because the event also reduced uncertainty. The site must show both effects separately.")]

# 16
story += [PageBreak()] + section("16", "Leaderboards and publication", "Product rules")
story += [P("Global and regional pages must make uncertainty, recency, and change explanations visible. Avoid presenting model estimates as exact truths."),
          P("Required team leaderboard fields", "H2x")]
story += [T([["Field","Example"], ["Global rank","#12"], ["Regional rank","Europe #3 / Country #1"],
             ["Public VCR","754"], ["Internal mu","1738.88"], ["Confidence","RD 48 - High"],
             ["Recent change","+29"], ["Last event","Silver S (1.35)"],
             ["Change explanation","+18.7 match, +5.0 contribution, +1.4 auto, +3.7 result"],
             ["Activity","8 days ago"]], [2.2*inch,4.9*inch])]
story += [P("Confidence labels", "H2x")]
story += [T([["RD","Label"], ["40-69","High"], ["70-119","Medium"], ["120-199","Low"], ["200-350","Provisional"]], [3.55*inch,3.55*inch])]
story += [P("Required event page fields", "H2x")]
story += bullets(["Tier, ESS, Event Weight, reliability, freeze timestamp, and roster snapshot.", "Each ESS component and its numeric score.", "Expected versus actual team percentile and VCR change decomposition.", "Tier eligibility ceiling and reason for any provisional status."])
story += [P("Required offense leaderboard fields", "H2x")]
story += bullets(["Adjusted OPR, standard error, conservative offense, sample size, region confidence, last event, and game season.", "Raw event OPR may be shown for context but must be clearly labeled non-global."])

# 17
story += [PageBreak()] + section("17", "Backtesting, calibration, and governance", "Model validation")
story += [P("All changes are evaluated chronologically. A model may train only on information available before the predicted match or event."),
          P("Primary validation metrics", "H2x")]
story += [T([["Metric","Target / use"], ["Match log loss","Primary optimization metric; lower is better"],
             ["Brier score","Probability accuracy"], ["Calibration error","Predicted 70% outcomes should occur about 70%"],
             ["Rank correlation","Future event performance versus current rating"],
             ["Regional calibration gap","Maximum 3 percentage-point win-probability error by region"],
             ["Tier calibration gap","Maximum 4 percentage-point error by event tier"]], [2.2*inch,4.9*inch])]
story += [P("Baselines", "H2x")]
story += bullets(["Win percentage only", "Plain Elo with K=20", "Raw OPR only", "Elo plus adjusted OPR", "Current VCR without Event Weight", "Current VCR without region shrinkage"])
story += [P("Parameter search ranges", "H2x")]
story += [T([["Parameter","Launch","Search range"], ["Elo scale","400","300-500"], ["Kmatch","20","12-32"],
             ["Evidence half-life","75 days","45-120"], ["Event K","80","50-110"],
             ["Elimination K","55","35-75"], ["Conservative RD multiplier","0.75","0.5-1.25"],
             ["Ridge lambda","8","1-32 log grid"], ["Partner softmax temperature","1.5","0.8-2.5"],
             ["Single-event positive cap","30%","20-40%"]], [2.6*inch,1.25*inch,3.25*inch], tiny=True)]
story += [P("Governance", "H2x"), P("Freeze model version, constants, and code hash for the competitive season. Publish change notes. Do not silently revise history. If an official score correction occurs, label the recalculation as data correction rather than model change. Maintain separate development and production leaderboards.")]

# 18
story += [PageBreak()] + section("18", "Implementation pseudocode", "Reference pipeline")
story += [P("The following order is normative; implementation language is not."),
          P("1. load season configuration and prior-season carryover<br/>2. initialize mu, RD, region, and component histories<br/>3. for each event in start-time order:<br/>&nbsp;&nbsp;a. freeze entrants, mu, RD, RSI, ESS, tier, and Event Weight<br/>&nbsp;&nbsp;b. for each official match in time order:<br/>&nbsp;&nbsp;&nbsp;&nbsp;i. compute alliance expectations<br/>&nbsp;&nbsp;&nbsp;&nbsp;ii. compute MOV and reliability<br/>&nbsp;&nbsp;&nbsp;&nbsp;iii. compute dynamic partner shares from prior local evidence<br/>&nbsp;&nbsp;&nbsp;&nbsp;iv. store match component deltas<br/>&nbsp;&nbsp;c. fit ridge offense, defense, autonomous, and residual models<br/>&nbsp;&nbsp;d. optionally recompute shares leave-one-match-out<br/>&nbsp;&nbsp;e. calculate qualification and elimination percentiles<br/>&nbsp;&nbsp;f. calculate event surprise and asymmetric Event Weight<br/>&nbsp;&nbsp;g. blend four component deltas and cap at +/-100<br/>&nbsp;&nbsp;h. update mu and RD<br/>&nbsp;&nbsp;i. append immutable audit record<br/>4. apply recency evidence weights at leaderboard query time<br/>5. compute ConservativeMu and PublicVCR<br/>6. publish global, regional, offense, defense, event, and ASE views", "Formula"),
          P("Numerical precision", "H2x")]
story += [T([["Value","Storage / rounding"], ["mu, RD, probabilities, deltas","64-bit float; retain at least 6 decimals"],
             ["Public VCR","Nearest integer, ordering by unrounded value"], ["ESS / RSI / ASE","One decimal displayed; full precision stored"],
             ["Event Weight","Two decimals displayed and stored from versioned table"],
             ["Timestamps","UTC ISO 8601"], ["Randomness","No randomness in production calculation"]], [2.5*inch,4.6*inch])]

# 19
story += [PageBreak()] + section("19", "Constants registry", "All launch numbers")
registry = [
    ["Constant","Value","Section"], ["New-team mu","1500","3"], ["New-team RD","350","3"],
    ["RD floor","40","3"], ["Returning RD cap","220","3"], ["Season carryover","40%","3"],
    ["Conservative RD multiplier","0.75","3"], ["Public scale multiplier","1.25","3"],
    ["Elo denominator scale","400","4"], ["Kmatch","20","4"], ["MOV coefficient","0.35","4"],
    ["Score-SD floor","12","4"], ["Partner softmax temperature","1.5","5"],
    ["Partner absolute bounds","20%-80%","5"], ["Ridge lambda","8.0","6/7"],
    ["Auto weights","60% residual / 40% contribution","7"],
    ["Qualification / elimination","35% / 65%","8"], ["Kelim","55","8"],
    ["Event K","80","10"], ["Event-close cap","+/-100","14"],
    ["ESS weights","30/25/15/15/10/5","9"], ["Event weights","0.70/0.82/0.95/1.15/1.35/1.60/1.85","9"],
    ["Region confidence denominator","12","11"], ["Recency half-life","75 days","12"],
    ["Inactivity grace","30 days","12"], ["RD inactivity growth","0.20/day","12"],
    ["Single positive event cap","30%","12"], ["ASE prior strength","5 decisions at score 50","13"],
    ["Final blend","55%/18%/10%/17%","14"], ["RD effective-match divisor","6","14"],
]
story += [T(registry, [2.55*inch,3.3*inch,1.25*inch], tiny=True),
          P("This registry is the authoritative launch-default summary. Detailed definitions and caps in the cited sections control if a shorthand entry appears ambiguous.", "Callout")]

# 20
story += [PageBreak()] + section("20", "Known limitations and launch checklist", "Operational readiness")
story += [P("Known limitations", "H2x")]
story += bullets([
    "Alliance-based scoring cannot perfectly identify individual contribution without richer telemetry.",
    "Disconnected regions remain uncertain until cross-region events create statistical anchors.",
    "Alliance selection contains private scouting and compatibility information the public model may not observe.",
    "Game-specific scoring changes require season-specific configuration and revalidation.",
    "Elimination advancement contains selection and bracket luck; caps and expectation adjustment reduce but do not remove it.",
])
story += [P("Launch checklist", "H2x")]
story += [T([["Check","Required status"], ["Official data adapters tested","Pass"], ["Season rules file versioned","Pass"],
             ["Chronological replay deterministic","Pass"], ["No future-data leakage tests","Pass"],
             ["Regional and tier calibration reported","Pass"], ["Rating-change decomposition sums exactly","Pass"],
             ["Score corrections reproducible","Pass"], ["Public methodology page matches production constants","Pass"],
             ["Baseline comparison published","Pass"], ["Model version and code hash displayed","Pass"]], [4.7*inch,2.4*inch])]
story += [Spacer(1,8), P("Recommended launch name", "H2x"),
          P("<b>VCR 2.0 - VEX Competitive Rating</b><br/>A predictive, opponent-adjusted, event-weighted global ranking system with regional confidence and transparent tournament-performance accounting.", "Callout"),
          P("End of specification.", "Note")]

SpecDoc(str(OUT)).build(story)
print(OUT)
