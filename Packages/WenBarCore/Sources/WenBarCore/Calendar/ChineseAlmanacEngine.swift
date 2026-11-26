import Foundation

public struct ChineseAlmanacInfo: Sendable, Equatable {
    public let yearPillar: String
    public let monthPillar: String
    public let dayPillar: String
    public let dayNaYin: String
    public let jianChu: String
    public let twelveSpirit: String
    public let isAuspiciousDay: Bool
    public let chongSha: String
    public let pengZu: String
    public let yi: [String]
    public let ji: [String]

    public var dayTypeLabel: String {
        isAuspiciousDay ? "黄道吉日" : "黑道日"
    }
}

/// Pure Swift Chinese Almanac (老黄历) calculation engine:
/// 干支三柱 (立春换年 / 节气换月 / JDN 算日), 纳音五行, 建除十二神, 黄道十二神, 冲煞, 彭祖百忌, 宜忌.
public enum ChineseAlmanacEngine {
    private static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let zodiacs = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]

    private static let jianChuNames = ["建", "除", "满", "平", "定", "执", "破", "危", "成", "收", "开", "闭"]
    private static let twelveSpirits = ["青龙", "明堂", "天刑", "朱雀", "金匮", "天德", "白虎", "玉堂", "天牢", "玄武", "司命", "勾陈"]
    private static let auspiciousIndices: Set<Int> = [0, 1, 4, 5, 7, 10]

    /// 30 pairs of 60 甲子 纳音 (each pair shares one NaYin for 2 consecutive sexagenary indices).
    private static let naYinPairs = [
        "海中金", "炉中火", "大林木", "路旁土", "剑锋金",
        "山头火", "涧下水", "城头土", "白蜡金", "杨柳木",
        "泉中水", "屋上土", "霹雳火", "松柏木", "长流水",
        "沙中金", "山下火", "平地木", "壁上土", "金箔金",
        "覆灯火", "天河水", "大驿土", "钗钏金", "桑柘木",
        "大溪水", "沙中土", "天上火", "石榴木", "大海水"
    ]

    private static let stemPengZu = [
        "甲不开仓财物耗散", "乙不栽植千株不长", "丙不修灶必见灾殃", "丁不剃头头必生疮", "戊不受田田主不祥",
        "己不破券二比并亡", "庚不经络织机虚张", "辛不合酱主人不尝", "壬不泱水更难提防", "癸不词讼理弱敌强"
    ]

    private static let branchPengZu = [
        "子不问卜自惹祸殃", "丑不冠带主不还乡", "寅不祭祀神鬼不尝", "卯不穿井水泉不香",
        "辰不哭泣必主重丧", "巳不远行财物伏藏", "午不苫盖屋主更张", "未不服药毒气入肠",
        "申不安床鬼祟入房", "酉不会客醉坐颠狂", "戌不吃犬作怪上床", "亥不嫁娶不利新郎"
    ]

    private static let gregorianCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }()

    public static func info(for date: Date) -> ChineseAlmanacInfo {
        let comps = gregorianCalendar.dateComponents([.year, .month, .day], from: date)
        let gYear = comps.year ?? 2026
        let gMonth = comps.month ?? 1
        let gDay = comps.day ?? 1

        // 1. Year Pillar (bounded by 立春)
        let liChunDay = LunarCalendarEngine.solarTermDay(year: gYear, index: 2)
        let solarYear = (gMonth < 2 || (gMonth == 2 && gDay < liChunDay)) ? (gYear - 1) : gYear
        let yearStemIdx = positiveMod(solarYear - 4, 10)
        let yearBranchIdx = positiveMod(solarYear - 4, 12)
        let yearPillar = "\(stems[yearStemIdx])\(branches[yearBranchIdx])"

        // 2. Month Pillar (bounded by even-indexed solar terms + 五虎遁)
        let termIndex = (gMonth - 1) * 2
        let termDay = LunarCalendarEngine.solarTermDay(year: gYear, index: termIndex)
        let monthBranchIdx = gDay >= termDay ? (gMonth % 12) : ((gMonth + 11) % 12)
        let offsetFromYin = positiveMod(monthBranchIdx - 2, 12)
        let yinStemIdx = ((yearStemIdx % 5) * 2 + 2) % 10
        let monthStemIdx = (yinStemIdx + offsetFromYin) % 10
        let monthPillar = "\(stems[monthStemIdx])\(branches[monthBranchIdx])"

        // 3. Day Pillar (Julian Day Number)
        let jdn = julianDayNumber(year: gYear, month: gMonth, day: gDay)
        let sexagenaryIdx = positiveMod(jdn + 49, 60)
        let dayStemIdx = sexagenaryIdx % 10
        let dayBranchIdx = sexagenaryIdx % 12
        let dayPillar = "\(stems[dayStemIdx])\(branches[dayBranchIdx])"
        let dayNaYin = naYinPairs[sexagenaryIdx / 2]

        // 4. 建除十二神
        let jianChuIdx = positiveMod(dayBranchIdx - monthBranchIdx, 12)
        let jianChu = jianChuNames[jianChuIdx]

        // 5. 黄道/黑道十二神
        let qingLongStart = positiveMod(monthBranchIdx - 2, 6) * 2
        let spiritIdx = positiveMod(dayBranchIdx - qingLongStart, 12)
        let twelveSpirit = twelveSpirits[spiritIdx]
        let isAuspicious = auspiciousIndices.contains(spiritIdx)

        // 6. 冲煞
        let clashBranchIdx = (dayBranchIdx + 6) % 12
        let shaDirection: String
        switch dayBranchIdx % 4 {
        case 0: shaDirection = "南"
        case 1: shaDirection = "西"
        case 2: shaDirection = "北"
        default: shaDirection = "东"
        }
        let chongSha = "冲\(zodiacs[clashBranchIdx]) 煞\(shaDirection)"

        // 7. 彭祖百忌
        let pengZu = "\(stemPengZu[dayStemIdx]) \(branchPengZu[dayBranchIdx])"

        // 8. 宜 / 忌
        let (yi, ji) = dailyActivities(jianChuIndex: jianChuIdx, isAuspicious: isAuspicious, dayBranchIdx: dayBranchIdx)

        return ChineseAlmanacInfo(
            yearPillar: yearPillar,
            monthPillar: monthPillar,
            dayPillar: dayPillar,
            dayNaYin: dayNaYin,
            jianChu: jianChu,
            twelveSpirit: twelveSpirit,
            isAuspiciousDay: isAuspicious,
            chongSha: chongSha,
            pengZu: pengZu,
            yi: yi,
            ji: ji
        )
    }

    private static func julianDayNumber(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    private static func positiveMod(_ a: Int, _ b: Int) -> Int {
        let m = a % b
        return m >= 0 ? m : m + b
    }

    private static func dailyActivities(jianChuIndex: Int, isAuspicious: Bool, dayBranchIdx: Int) -> ([String], [String]) {
        // Traditional 建除十二神 activity mapping
        let baseTable: [(yi: [String], ji: [String])] = [
            // 0: 建
            (["出行", "会友", "赴任", "祈福", "纳财"], ["动土", "开仓", "嫁娶", "安葬"]),
            // 1: 除
            (["祭祀", "扫舍", "沐浴", "求医", "解除"], ["嫁娶", "出行", "开市", "入宅"]),
            // 2: 满
            (["祈福", "开市", "立券", "纳财", "移徙"], ["动土", "裁衣", "栽种", "安葬"]),
            // 3: 平
            (["修饰垣墙", "平治道涂", "扫舍", "修造"], ["嫁娶", "开市", "破土", "出行"]),
            // 4: 定
            (["嫁娶", "订盟", "会友", "祭祀", "入学"], ["诉讼", "出行", "动土", "伐木"]),
            // 5: 执
            (["祭祀", "祈福", "捕捉", "立券", "纳采"], ["开市", "移徙", "出行", "破土"]),
            // 6: 破
            (["破屋", "坏垣", "求医", "治病"], ["嫁娶", "签约", "开市", "移徙", "出行"]),
            // 7: 危
            (["祭祀", "祈福", "安床", "拆卸", "入殓"], ["登高", "行船", "出行", "动土"]),
            // 8: 成
            (["开市", "签约", "嫁娶", "入宅", "出行", "求学"], ["诉讼", "词讼", "安葬"]),
            // 9: 收
            (["纳财", "收获", "祭祀", "修仓", "捕捉"], ["开市", "出行", "安葬", "破土"]),
            // 10: 开
            (["开市", "交易", "出行", "入宅", "嫁娶", "祈福"], ["安葬", "动土", "破土"]),
            // 11: 闭
            (["修造", "筑堤", "补垣", "塞穴", "祭祀"], ["开市", "出行", "嫁娶", "求医"])
        ]

        var yi = baseTable[jianChuIndex].yi
        var ji = baseTable[jianChuIndex].ji

        if isAuspicious && !yi.contains("祈福") && jianChuIndex != 6 {
            yi.insert("祈福", at: 0)
        }
        if !isAuspicious && !ji.contains("远行") && !ji.contains("出行") {
            ji.append("远行")
        }
        if dayBranchIdx == 6 && !ji.contains("苫盖") {
            // Keep concise max 5 items each
        }

        return (Array(yi.prefix(5)), Array(ji.prefix(5)))
    }
}
