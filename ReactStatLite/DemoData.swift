import Foundation

// MARK: - Demo Data for Ad Purposes

struct DemoData {
    
    static let worldLeaders: [String] = [
        "Donald Trump",
        "Benjamin Netanyahu", 
        "Kim Jong Un",
        "Vladimir Putin",
        "Joe Biden",
        "Emmanuel Macron",
        "Rishi Sunak",
        "Olaf Scholz",
        "Ursula von der Leyen",
        "Jair Bolsonaro",
        "Justin Trudeau",
        "Xi Jinping"
    ]
    
    // Mapping from demo phone numbers to world leader names for the ContactNameCache
    static let demoPhoneMapping: [String: String] = [
        "+12025551234": "Donald Trump",
        "+972541234567": "Benjamin Netanyahu",
        "+850212345678": "Kim Jong Un",
        "+74951234567": "Vladimir Putin",
        "+12024561111": "Joe Biden",
        "+33123456789": "Emmanuel Macron",
        "+442012345678": "Rishi Sunak",
        "+493012345678": "Olaf Scholz",
        "+3221234567": "Ursula von der Leyen",
        "+552112345678": "Jair Bolsonaro",
        "+16131234567": "Justin Trudeau",
        "+861012345678": "Xi Jinping"
    ]
    
    static func createDemoChat() -> ChatThread {
        let demoHandles = Array(demoPhoneMapping.keys)
        
        return ChatThread(
            id: -1, // Negative ID to indicate demo
            chatIdentifier: "demo-world-leaders-summit",
            displayName: "World Leaders Summit 🌍",
            messageCount: 847,
            participantCount: worldLeaders.count,
            participantHandles: demoHandles
        )
    }
    
    // Demo message counts to create realistic stats
    static let demoMessageCounts: [String: Int] = [
        "Donald Trump": 156,
        "Benjamin Netanyahu": 134,
        "Kim Jong Un": 89,
        "Vladimir Putin": 112,
        "Joe Biden": 98,
        "Emmanuel Macron": 76,
        "Rishi Sunak": 54,
        "Olaf Scholz": 43,
        "Ursula von der Leyen": 38,
        "Jair Bolsonaro": 29,
        "Justin Trudeau": 12,
        "Xi Jinping": 6
    ]
    
    // Demo reaction data - engineered for big names to dominate advanced stats
    static let demoLaughReactions: [(from: String, to: String, count: Int)] = [
        // TRUMP GLAZING NETANYAHU (make him Biggest Glazer)
        ("Donald Trump", "Benjamin Netanyahu", 300), // MASSIVE number
        ("Donald Trump", "Joe Biden", 2), // Very low number to maintain high share
        ("Donald Trump", "Vladimir Putin", 1),
        ("Donald Trump", "Kim Jong Un", 1),
        
        // KIM & PUTIN MUTUAL GLAZING (make them Biggest Mutual Glazers but not Biggest Glazer)
        ("Kim Jong Un", "Vladimir Putin", 20),
        ("Vladimir Putin", "Kim Jong Un", 22),
        
        // NETANYAHU giving many reactions back to Trump (so Trump isn't ignored)
        ("Benjamin Netanyahu", "Donald Trump", 80),
        ("Benjamin Netanyahu", "Joe Biden", 5),
        ("Benjamin Netanyahu", "Vladimir Putin", 2),
        
        // PUTIN giving very few reactions to not compete for Biggest Glazer
        ("Vladimir Putin", "Donald Trump", 3),
        ("Vladimir Putin", "Benjamin Netanyahu", 1),
        
        // KIM giving some reactions to Trump (so Trump isn't ignored)
        ("Kim Jong Un", "Donald Trump", 15),
        ("Kim Jong Un", "Benjamin Netanyahu", 2),
        
        // Others giving reactions to Trump (so Trump isn't ignored)
        ("Joe Biden", "Donald Trump", 25),
        ("Joe Biden", "Benjamin Netanyahu", 3),
        ("Emmanuel Macron", "Donald Trump", 12),
        ("Emmanuel Macron", "Olaf Scholz", 1),
        ("Olaf Scholz", "Donald Trump", 8),
        ("Olaf Scholz", "Emmanuel Macron", 1),
        ("Rishi Sunak", "Donald Trump", 6),
        ("Rishi Sunak", "Joe Biden", 1),
        ("Justin Trudeau", "Donald Trump", 4),
        ("Justin Trudeau", "Joe Biden", 1),
        ("Jair Bolsonaro", "Donald Trump", 10),
        ("Jair Bolsonaro", "Joe Biden", 1),
        ("Xi Jinping", "Vladimir Putin", 1),
        ("Xi Jinping", "Donald Trump", 3),
        ("Ursula von der Leyen", "Donald Trump", 7),
        ("Ursula von der Leyen", "Olaf Scholz", 1),
    ]
    
    // Demo reactions of all kinds for the new stats - BIG NAMES DOMINATE
    static let demoAllReactions: [(from: String, to: String, kind: ReactionKind, count: Int)] = [
        // Laugh reactions (😂) - MAIN STATS
        ("Donald Trump", "Benjamin Netanyahu", .laughed, 300),
        ("Donald Trump", "Joe Biden", .laughed, 2),
        ("Donald Trump", "Vladimir Putin", .laughed, 1),
        ("Donald Trump", "Kim Jong Un", .laughed, 1),
        
        ("Kim Jong Un", "Vladimir Putin", .laughed, 20),
        ("Vladimir Putin", "Kim Jong Un", .laughed, 22),
        
        ("Benjamin Netanyahu", "Donald Trump", .laughed, 80),
        ("Benjamin Netanyahu", "Joe Biden", .laughed, 5),
        ("Benjamin Netanyahu", "Vladimir Putin", .laughed, 2),
        
        ("Vladimir Putin", "Donald Trump", .laughed, 3),
        ("Vladimir Putin", "Benjamin Netanyahu", .laughed, 1),
        
        ("Kim Jong Un", "Donald Trump", .laughed, 15),
        ("Kim Jong Un", "Benjamin Netanyahu", .laughed, 2),
        
        // Others giving reactions to Trump (so Trump isn't ignored)
        ("Joe Biden", "Donald Trump", .laughed, 25),
        ("Joe Biden", "Benjamin Netanyahu", .laughed, 3),
        ("Emmanuel Macron", "Donald Trump", .laughed, 12),
        ("Emmanuel Macron", "Olaf Scholz", .laughed, 1),
        ("Olaf Scholz", "Donald Trump", .laughed, 8),
        ("Olaf Scholz", "Emmanuel Macron", .laughed, 1),
        ("Rishi Sunak", "Donald Trump", .laughed, 6),
        ("Rishi Sunak", "Joe Biden", .laughed, 1),
        ("Justin Trudeau", "Donald Trump", .laughed, 4),
        ("Justin Trudeau", "Joe Biden", .laughed, 1),
        ("Jair Bolsonaro", "Donald Trump", .laughed, 10),
        ("Jair Bolsonaro", "Joe Biden", .laughed, 1),
        ("Xi Jinping", "Vladimir Putin", .laughed, 1),
        ("Xi Jinping", "Donald Trump", .laughed, 3),
        ("Ursula von der Leyen", "Donald Trump", .laughed, 7),
        ("Ursula von der Leyen", "Olaf Scholz", .laughed, 1),
        
        // Love reactions (❤️) - BIG NAMES
        ("Donald Trump", "Benjamin Netanyahu", .loved, 40),
        ("Benjamin Netanyahu", "Donald Trump", .loved, 35),
        ("Vladimir Putin", "Kim Jong Un", .loved, 15),
        ("Kim Jong Un", "Vladimir Putin", .loved, 12),
        
        // Like reactions (👍) - BIG NAMES
        ("Donald Trump", "Vladimir Putin", .liked, 20),
        ("Vladimir Putin", "Donald Trump", .liked, 8),
        ("Kim Jong Un", "Benjamin Netanyahu", .liked, 15),
        ("Benjamin Netanyahu", "Kim Jong Un", .liked, 10),
        
        // Emphasized reactions (‼️) - BIG NAMES
        ("Donald Trump", "Joe Biden", .emphasized, 12),
        ("Joe Biden", "Donald Trump", .emphasized, 8),
        ("Kim Jong Un", "Emmanuel Macron", .emphasized, 6),
        
        // Very few other reactions
        ("Joe Biden", "Ursula von der Leyen", .liked, 2),
        ("Emmanuel Macron", "Joe Biden", .liked, 2),
        ("Rishi Sunak", "Joe Biden", .liked, 1),
        ("Justin Trudeau", "Joe Biden", .liked, 1),
        ("Jair Bolsonaro", "Donald Trump", .emphasized, 3),
        ("Xi Jinping", "Donald Trump", .questioned, 2),
        ("Joe Biden", "Donald Trump", .disliked, 2),
        ("Donald Trump", "Joe Biden", .disliked, 1),
    ]
}
