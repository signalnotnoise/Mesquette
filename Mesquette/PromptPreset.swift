// PromptPreset.swift
// Mesquette — Curated text-to-3D prompt library (Shap-E + Director)

import Foundation

/// High-level theme for browsing presets.
nonisolated enum PromptCategory: String, CaseIterable, Identifiable, Sendable {
    case scenes
    case animals
    case characters
    case vehicles
    case furniture
    case architecture
    case nature
    case food
    case props
    case fantasy
    case abstract

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scenes:        return "Scenes"
        case .animals:       return "Animals"
        case .characters:    return "Characters"
        case .vehicles:      return "Vehicles"
        case .furniture:     return "Furniture"
        case .architecture:  return "Buildings"
        case .nature:        return "Nature"
        case .food:          return "Food"
        case .props:         return "Props"
        case .fantasy:       return "Fantasy"
        case .abstract:      return "Abstract"
        }
    }

    var systemImage: String {
        switch self {
        case .scenes:        return "square.grid.3x3.fill"
        case .animals:       return "pawprint.fill"
        case .characters:    return "figure.stand"
        case .vehicles:      return "car.fill"
        case .furniture:     return "sofa.fill"
        case .architecture:  return "building.2.fill"
        case .nature:        return "leaf.fill"
        case .food:          return "fork.knife"
        case .props:         return "cube.fill"
        case .fantasy:       return "wand.and.stars"
        case .abstract:      return "circle.hexagongrid.fill"
        }
    }
}

/// A single ready-to-run prompt suggestion.
nonisolated struct PromptPreset: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Scenes: a directed tabletop brief the compiler can split. Singles: one subject.
    let prompt: String
    let category: PromptCategory
    let systemImage: String

    init(
        id: String? = nil,
        title: String,
        prompt: String,
        category: PromptCategory,
        systemImage: String? = nil
    ) {
        self.id = id ?? "\(category.rawValue)-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))"
        self.title = title
        self.prompt = prompt
        self.category = category
        self.systemImage = systemImage ?? category.systemImage
    }
}

/// Catalog of presets organized for browsing.
nonisolated enum PromptPresetLibrary {

    static let all: [PromptPreset] = scenes + animals + characters + vehicles + furniture
        + architecture + nature + food + props + fantasy + abstract

    static func presets(in category: PromptCategory) -> [PromptPreset] {
        all.filter { $0.category == category }
    }

    // MARK: - Scenes
    // Directed scenes. Name 5–6 chunky closed volumes (mug, loaf, lantern,
    // barrel, closed book). Never paper, pens, cobbles, fog, or a ground mesh.

    static let scenes: [PromptPreset] = [
        .init(
            title: "Breakfast",
            prompt: "weekend breakfast for one on a round wooden table: a thick white ceramic mug of coffee with a glossy glaze, a golden laminated croissant, a small stoneware bowl of blueberries, a squat glass jar of orange marmalade with a wooden lid, honey-gold crusts and steam in cool morning side light",
            category: .scenes,
            systemImage: "cup.and.saucer.fill"
        ),
        .init(
            title: "Writing Desk",
            prompt: "a night writing desk under a pool of lamp light: a brass banker's lamp with a green glass cowl, a closed oxblood leather journal with metal clasps, a stoneware mug gone cold, a tiny potted succulent in a terracotta dish, walnut grain and green glass glow",
            category: .scenes,
            systemImage: "lamp.desk.fill"
        ),
        .init(
            title: "Afternoon Tea",
            prompt: "afternoon tea for one: a round porcelain teapot with a curved spout, a matching cup on a thick saucer, a three-tier stand holding scones and jam pots as one chunky piece, a small milk jug, bone-white china, rose-gold rims, late sun",
            category: .scenes,
            systemImage: "leaf.fill"
        ),
        .init(
            title: "Picnic",
            prompt: "a sunny picnic cluster: a wicker hamper with leather straps as the hero, a corked green wine bottle, a round wheel of cheese, a ceramic jug of lemonade, a closed loaf wrapped as a fat oval, straw gold and glass green on warm afternoon light",
            category: .scenes,
            systemImage: "basket.fill"
        ),
        .init(
            title: "Still Life",
            prompt: "a Dutch still life on dark wood: a pewter jug with a hinged lid, a glass carafe of red wine, a cut pomegranate showing ruby seeds as a chunky hemisphere, a brass candlestick with a short candle, chiaroscuro, pewter and garnet",
            category: .scenes,
            systemImage: "wineglass.fill"
        ),
        .init(
            title: "Camp Table",
            prompt: "a dusk camp table in pine country: a blackened kettle on a stubby iron stand, a tin enamel mug, a closed kerosene lantern with a wire cage, a round wooden cutting board with a sausage as one chunky piece, orange firelight, enamel chips, smoke-blue air",
            category: .scenes,
            systemImage: "tent.fill"
        ),
        .init(
            title: "Garden Bench",
            prompt: "a quiet garden corner: a weathered stone birdbath as the hero, a terracotta pot of a round boxwood, a pair of rubber garden boots as one chunky pair, a metal watering can with a fat rose head, moss, clay, and pewter under dappled late light",
            category: .scenes,
            systemImage: "leaf.circle.fill"
        ),
        .init(
            title: "Beach",
            prompt: "toys left after low tide: a fat red beach ball, a yellow plastic bucket with a molded castle rim, a closed wicker picnic bottle of sunscreen as a squat cylinder, a spiral conch shell, salt-white and primary colors on bright noon light",
            category: .scenes,
            systemImage: "beach.umbrella.fill"
        ),
        .init(
            title: "Bakery",
            prompt: "a neighborhood bakery at first light: a flour-dusted round sourdough boule as the hero, a glazed cinnamon roll on a thick ceramic plate, a white diner mug of black coffee, a squat glass jar of apricot jam with a wooden lid, crust-gold, copper, and steam in window light",
            category: .scenes,
            systemImage: "birthday.cake.fill"
        ),
        .init(
            title: "Knight's Kit",
            prompt: "a knight's kit laid out before a ride: a closed barrel-visored helmet, a round wooden shield with a painted lion, a sheathed arming sword as a chunky scabbard, a leather waterskin, steel, oak, and oxblood leather under chapel light",
            category: .scenes,
            systemImage: "shield.fill"
        ),
        .init(
            title: "Alchemist",
            prompt: "an alchemist's work table at violet hour: a round-bottom flask of green liquor as the hero, a closed leather grimoire with iron clasps, a cluster of amethyst crystals, a small brass astrolabe, glass, verdigris, and candle-warm metal",
            category: .scenes,
            systemImage: "flask.fill"
        ),
        .init(
            title: "Game Night",
            prompt: "game night just before the first roll: a chunky wooden dice tower, a pair of oversized six-sided dice, a closed wooden card box with a sliding lid, a ceramic tankard of ale, walnut, ivory pips, and tavern-gold light",
            category: .scenes,
            systemImage: "dice.fill"
        ),
        .init(
            title: "Artist Desk",
            prompt: "an artist's desk after a long sitting: a closed linen-bound sketchbook, a fat ceramic mug of tea, a round glass jar of cobalt paint, a small unglazed clay vase, a wooden palette as a thick oval slab, pigment-stained wood and north-window light",
            category: .scenes,
            systemImage: "paintpalette.fill"
        ),
        .init(
            title: "Music Corner",
            prompt: "a practice corner on a rug: a small acoustic guitar standing as the hero, a round three-legged wooden stool, a closed hard guitar case, a ceramic mug, honey spruce, worn ebony, and late-afternoon amber",
            category: .scenes,
            systemImage: "guitars.fill"
        ),
        .init(
            title: "Sushi Bar",
            prompt: "a quiet sushi counter for one: a thick hinoki cutting block as a chunky slab, a ceramic soy pourer, a lacquered rice tub with a lid, a plump nigiri pair as one piece, pale wood, black lacquer, and cool overhead light",
            category: .scenes,
            systemImage: "fish.fill"
        ),
        .init(
            title: "Toy Shelf",
            prompt: "a child's favorites pulled onto the floor: a plump teddy bear sitting, a wooden pull-along duck on wheels, a chunky red toy fire engine, a spinning top, wool, painted wood, and nursery-warm light",
            category: .scenes,
            systemImage: "teddybear.fill"
        ),
        .init(
            title: "Forest",
            prompt: "a misty old-growth clearing: an ancient oak with a thick gnarled trunk as the hero, a wet gray boulder, a cluster of red toadstools as one chunky clump, a fallen mossy log, dawn pale through the canopy, bark, stone, and scarlet caps",
            category: .scenes,
            systemImage: "tree.fill"
        ),
        .init(
            title: "Castle",
            prompt: "a hilltop keep: a compact pale-stone castle with four round towers as one mesh, a wooden well with a peaked roof, a two-wheel hay cart, a closed oak barrel, late-afternoon gold on limestone and iron bands",
            category: .scenes,
            systemImage: "building.columns.fill"
        ),
        .init(
            title: "Harbor",
            prompt: "a tiny fishing harbor at low tide: a squat red-and-white lighthouse as the hero, a moored sailboat with one sail furled, a wooden crate of coiled rope as one chunky crate, a weathered barrel, salt-bleached wood, wet iron, and silver morning",
            category: .scenes,
            systemImage: "sailboat.fill"
        ),
        .init(
            title: "Japanese Garden",
            prompt: "a Japanese garden corner: a stone tōrō lantern as the hero, a twisted bonsai in a glazed ceramic oval pot, a small arched red wooden bridge as one piece, a fat water basin stone, raked-sand implied by the studio floor, quiet overcast light",
            category: .scenes,
            systemImage: "fan.fill"
        ),
        .init(
            title: "Desert Oasis",
            prompt: "a noon oasis diorama: a squat date palm with a thick trunk as the hero, a clay water amphora, a low beige tent as one chunky volume, a round brass tray with a teapot as one piece, heat, sand-gold, and hard shadows",
            category: .scenes,
            systemImage: "sun.max.fill"
        ),
        .init(
            title: "Snow Village",
            prompt: "a snowbound village square at dusk: a timber cabin with a thick snow cap on the roof as the hero, a conical evergreen, a glowing iron lantern on a post, a wooden sled with curled runners as one chunky piece, chimney-warm windows, pine, and blue hour",
            category: .scenes,
            systemImage: "snowflake"
        ),
        .init(
            title: "Pirate Wreck",
            prompt: "a pirate wreck on a sandbar: a broken ship's wheel as a thick wooden ring, a closed iron-banded treasure chest, a weathered rum barrel, a brass spyglass as a short fat cylinder, sea-spray, tar, and late sun",
            category: .scenes,
            systemImage: "flag.fill"
        ),
        .init(
            title: "Wizard Tower",
            prompt: "the foot of a wizard's tower at violet dusk: a round stone turret as the hero, a crystal orb on a clawed stand, a closed spellbook with a jeweled clasp, an iron cauldron, amethyst light, wet stone, and brass",
            category: .scenes,
            systemImage: "sparkles"
        ),
        .init(
            title: "Market Stall",
            prompt: "a spice-market stall at evening: a striped canvas awning over a wooden cart as one chunky stall, stacked ceramic spice jars as a cluster, a hanging brass lantern, a fat sack of grain tied at the neck, cumin-gold, copper, and warm dusk",
            category: .scenes,
            systemImage: "storefront.fill"
        ),
        .init(
            title: "Reef",
            prompt: "a shallow coral garden: a brain-coral mound as the hero, a sea turtle swimming, a sunken clay amphora, a cluster of staghorn coral as one chunky piece, tropical cyan water and dappled sun",
            category: .scenes,
            systemImage: "water.waves"
        ),
        .init(
            title: "Autumn Orchard",
            prompt: "an autumn orchard path: a gnarled apple tree heavy with red fruit as the hero, a wooden harvest barrel, a wicker basket heaped with apples as one piece, a stone cider jug, gold late-day light, russet and oak",
            category: .scenes,
            systemImage: "carrot.fill"
        ),
        .init(
            title: "Cathedral Square",
            prompt: "a rainy cathedral square diorama: a compact gothic church with one spire as the hero, a stone fountain with a round basin, a parked closed carriage, a glowing iron lantern, wet limestone, black lacquer, and pewter sky",
            category: .scenes,
            systemImage: "building.2.fill"
        ),
        .init(
            title: "Viking Camp",
            prompt: "a viking shore camp: a turf-roofed longhouse as the hero, a beached clinker longboat, a round painted shield on a post, a closed wooden chest, cold sea wind, pine tar, and iron bosses",
            category: .scenes,
            systemImage: "shield.lefthalf.filled"
        ),
        .init(
            title: "Moon Outpost",
            prompt: "a lonely moon outpost: a squat cylindrical habitat module as the hero, a six-wheeled rover, a dish antenna on a short mast, a crate of white sample canisters, gray regolith implied by the floor, hard vacuum shadows",
            category: .scenes,
            systemImage: "moon.fill"
        ),
        .init(
            title: "Ruined Temple",
            prompt: "a ruined jungle shrine: a cracked stone stepped pyramid as the hero, a fallen fluted column as one chunky drum, a mossy seated idol, a clay offering bowl, vines only as color on stone, humid green shade",
            category: .scenes,
            systemImage: "leaf.arrow.triangle.circlepath"
        ),
        .init(
            title: "Ramen Stall",
            prompt: "a night ramen stall for one: a heavy ceramic ramen bowl heaped as one chunky volume, a squat soy dispenser, a bamboo steamer basket with a lid, a paper lantern as a round glowing globe, lacquer red, steam-white, and neon-warm night",
            category: .scenes,
            systemImage: "flame.fill"
        ),
        .init(
            title: "Pottery Bench",
            prompt: "a potter's bench after throwing: a kick wheel as a thick round platter, a wet clay cylinder on the bat as the hero, a stoneware water bucket, a cluster of finished mugs as one group, slip-gray, terracotta, and north light",
            category: .scenes,
            systemImage: "aqi.medium"
        ),
        .init(
            title: "Observatory",
            prompt: "a dome observatory at 2 a.m.: a squat white dome with an open slit as the hero, a fat reflecting telescope on a fork mount, a closed wooden stool, a brass marine clock, cold starlight, enamel, and oil-black metal",
            category: .scenes,
            systemImage: "sparkle"
        ),
        .init(
            title: "Watchmaker",
            prompt: "a watchmaker's bench under a loupe lamp: a brass desk lamp with a round magnifier, a closed mahogany watch case, a fat velvet-lined cushion with a pocket watch as one piece, a ceramic cup of tea, walnut, brass, and quiet green glass",
            category: .scenes,
            systemImage: "clock.fill"
        ),
        .init(
            title: "Greenhouse",
            prompt: "a potting bench in a glasshouse: a galvanized watering can as the hero, a row of terracotta pots as one chunky cluster, a closed seed tin, a stoneware crock of compost, wet clay, zinc, and humid noon",
            category: .scenes,
            systemImage: "humidity.fill"
        ),
        .init(
            title: "Record Shelf",
            prompt: "a listening corner: a wooden crate of vinyl as a chunky block, a round-cornered record player with a closed lid, a pair of bookshelf speakers as one stereo pair, a ceramic mug, walnut, black vinyl, and amber lamp light",
            category: .scenes,
            systemImage: "opticaldisc.fill"
        ),
        .init(
            title: "Blacksmith",
            prompt: "a smithy at the anvil: a heavy steel anvil as the hero, a glowing forge as a chunky brick volume, a closed water barrel, a leather apron draped over a stump as one piece, coal orange, iron, and soot",
            category: .scenes,
            systemImage: "hammer.fill"
        ),
        .init(
            title: "Apothecary",
            prompt: "an apothecary counter: a row of amber glass bottles as one cluster, a brass mortar and pestle, a closed wooden herb cabinet as a small chest, a ceramic ointment jar, bottle-green, brass, and apothecary-gold labels as color not paper",
            category: .scenes,
            systemImage: "pills.fill"
        ),
        .init(
            title: "Chess Endgame",
            prompt: "a chess endgame as four chunky pieces, no board mesh: a tall white king, a black queen, a rook, a fallen knight on its side, boxwood and ebony, raking gallery light",
            category: .scenes,
            systemImage: "crown.fill"
        ),
        .init(
            title: "Dim Sum Cart",
            prompt: "a dim-sum trolley: a stacked bamboo steamer tower as the hero, a ceramic teapot, a soy cruet, a round lazy-susan dish of dumplings as one chunky plate, lacquer, steam, and banquet-gold light",
            category: .scenes,
            systemImage: "fork.knife"
        ),
        .init(
            title: "Tackle Bench",
            prompt: "a fishing bench at dawn: a closed wooden tackle box as the hero, a coiled landing net as a chunky hoop, a thermos flask, a round bobber float, cedar, enamel green, and river-silver light",
            category: .scenes,
            systemImage: "fish.fill"
        ),
        .init(
            title: "Radio Shack",
            prompt: "a 1970s radio bench: a wood-cased shortwave receiver as the hero, a round bakelite microphone, a chunky analog multimeter, a ceramic mug, teak, ivory knobs, and warm tube glow",
            category: .scenes,
            systemImage: "radio.fill"
        ),
        .init(
            title: "Ship's Chart",
            prompt: "a captain's chart table: a brass binnacle compass as the hero, a closed leather logbook, a kerosene lantern, a fat brass spyglass, mahogany, verdigris, and cabin-gold light",
            category: .scenes,
            systemImage: "location.north.circle.fill"
        ),
    ]

    // MARK: - Animals

    static let animals: [PromptPreset] = [
        .init(title: "Golden Retriever", prompt: "a golden retriever sitting, honey coat, soft ears, friendly open mouth", category: .animals),
        .init(title: "Tabby Cat", prompt: "an orange tabby cat sitting upright, striped fur, thick tail curled around paws", category: .animals),
        .init(title: "Snow Owl", prompt: "a snowy owl perched, white plumage, black beak, round yellow eyes, compact", category: .animals),
        .init(title: "African Elephant", prompt: "a small African elephant standing, wrinkled gray hide, curved tusks, flared ears", category: .animals),
        .init(title: "Red Fox", prompt: "a red fox sitting, white chest, black socks, bushy tail wrapped, alert ears", category: .animals),
        .init(title: "Emperor Penguin", prompt: "an emperor penguin standing upright, black-and-white tuxedo, orange neck patch", category: .animals),
        .init(title: "Blue Morpho", prompt: "a blue morpho butterfly, wings open in a chunky V, iridescent sapphire", category: .animals),
        .init(title: "Koi", prompt: "a fat kohaku koi, white body with red patches, flowing tail, compact swimming pose", category: .animals),
        .init(title: "Draft Horse", prompt: "a chestnut draft horse standing, blond mane and feathered hooves, heavy build", category: .animals),
        .init(title: "Angora Rabbit", prompt: "a white angora rabbit sitting, extra-long fur, pink ears, round loaf pose", category: .animals),
        .init(title: "Sea Turtle", prompt: "a green sea turtle, patterned scutes, flippers mid-stroke, compact shell", category: .animals),
        .init(title: "Bald Eagle", prompt: "a bald eagle perched, white head, hooked beak, folded dark wings, yellow talons", category: .animals),
        .init(title: "Red Panda", prompt: "a red panda sitting, rust fur, ringed tail, round face, chunky stuffed-animal silhouette", category: .animals),
        .init(title: "Octopus", prompt: "a plump octopus, coiled tentacles as one closed volume, mottled orange-brown", category: .animals),
        .init(title: "Corgi", prompt: "a Pembroke corgi standing, fox-red coat, stubby legs, big ears, loaf-like body", category: .animals),
        .init(title: "Axolotl", prompt: "a pink axolotl, feathery external gills, smiling mouth, chubby closed form", category: .animals),
    ]

    // MARK: - Characters

    static let characters: [PromptPreset] = [
        .init(title: "Companion Robot", prompt: "a friendly appliance robot, round head, glowing cyan eyes, squat white body, rubber tracks", category: .characters),
        .init(title: "Apollo Astronaut", prompt: "an Apollo-era astronaut standing, white A7L suit, gold visor down, chunky PLSS backpack", category: .characters),
        .init(title: "Plate Knight", prompt: "a late-medieval knight in polished plate, closed visor, heater shield, standing at rest", category: .characters),
        .init(title: "Hedge Wizard", prompt: "an old wizard, long gray beard, cobalt robe, pointed hat, gnarled staff, hunched", category: .characters),
        .init(title: "Shinobi", prompt: "a ninja in matte black gi, wrapped face, crouched, compact silhouette", category: .characters),
        .init(title: "Privateer", prompt: "a pirate captain, tricorn, long coat, one peg leg, closed spyglass at the hip", category: .characters),
        .init(title: "Greyship Alien", prompt: "a cute gray alien, oversized black eyes, small body, three-fingered hands, standing", category: .characters),
        .init(title: "Cape Hero", prompt: "a superhero in a crimson cape, chunky chest emblem, fists on hips, comic silhouette", category: .characters),
        .init(title: "Pastry Chef", prompt: "a pastry chef, tall toque, white double-breasted jacket, holding a round cake dome", category: .characters),
        .init(title: "Red Samurai", prompt: "a samurai in lacquered red ō-yoroi, closed mempo, katana sheathed, standing", category: .characters),
        .init(title: "Deep Diver", prompt: "a 1930s hard-hat diver, copper helmet, canvas suit, lead boots, standing", category: .characters),
        .init(title: "Steampunk Pilot", prompt: "a steampunk aviator, leather cap, brass goggles, bomber jacket, standing", category: .characters),
        .init(title: "Stone Golem", prompt: "a mossy stone golem, boulder limbs as one closed figure, glowing cracks, standing", category: .characters),
        .init(title: "Mecha Pilot", prompt: "a chunky toy mecha, rounded armor plates, visor slit, standing at rest, no thin antennas", category: .characters),
    ]

    // MARK: - Vehicles

    static let vehicles: [PromptPreset] = [
        .init(title: "Berlinetta", prompt: "a 1960s Italian berlinetta, electric cobalt, long hood, short deck, chrome knock-offs", category: .vehicles),
        .init(title: "Farm Truck", prompt: "a 1950s red pickup, rounded fenders, wooden bed rails, whitewall tires, chunky", category: .vehicles),
        .init(title: "School Bus", prompt: "a classic American school bus, chrome yellow, black stripes, pug-nosed, compact toy scale", category: .vehicles),
        .init(title: "Cafe Racer", prompt: "a black cafe-racer motorcycle, clip-ons, round headlamp, compact tank, chrome pipes", category: .vehicles),
        .init(title: "Daysailer", prompt: "a small white daysailer, varnished wood cockpit, one furled sail as a chunky boom", category: .vehicles),
        .init(title: "Rescue Helo", prompt: "a red rescue helicopter, bubble cockpit, closed rotor disc as one volume, pontoon skids", category: .vehicles),
        .init(title: "Barnstormer", prompt: "a yellow barnstormer biplane, stacked wings as thick slabs, round engine, two-blade prop", category: .vehicles),
        .init(title: "Moon Rocket", prompt: "a silver V-2 style rocket standing on fins, riveted skin, black nose cone", category: .vehicles),
        .init(title: "Iron Horse", prompt: "a black steam locomotive, cowcatcher, round boiler, red wheels, compact toy engine", category: .vehicles),
        .init(title: "Vespa", prompt: "a teal 1960s scooter, round headlamp, fat fenders, chrome mirrors as nubs, chunky", category: .vehicles),
        .init(title: "Scout Tank", prompt: "a small green recon tank, rounded turret, short barrel, wide tracks as one closed hull", category: .vehicles),
        .init(title: "Hot Air Balloon", prompt: "a striped hot-air balloon, fat teardrop envelope, wicker basket, primary colors", category: .vehicles),
        .init(title: "Tugboat", prompt: "a stubby harbor tug, black hull, red house, fat fenders, chunky smokestack", category: .vehicles),
        .init(title: "Cable Car", prompt: "a San Francisco cable car, wood-and-brass, running boards, compact streetcar body", category: .vehicles),
        .init(title: "Submersible", prompt: "a yellow deep-sea submersible, round viewport, manipulator as a stubby arm, squat", category: .vehicles),
    ]

    // MARK: - Furniture

    static let furniture: [PromptPreset] = [
        .init(title: "Windsor Chair", prompt: "a Windsor side chair, turned spindles as a thick back, elm seat, four splayed legs", category: .furniture),
        .init(title: "Chesterfield", prompt: "a tufted oxblood chesterfield sofa, rolled arms, deep buttons, short turned legs", category: .furniture),
        .init(title: "Banker's Lamp", prompt: "a brass banker's lamp, green glass cowl, pull chain as a nub, heavy rectangular base", category: .furniture),
        .init(title: "Ladder Shelf", prompt: "a short oak ladder bookshelf, three thick shelves, a few chunky bound books as color", category: .furniture),
        .init(title: "Drum Table", prompt: "a round drum coffee table, walnut top, pedestal base, short and chunky", category: .furniture),
        .init(title: "Captain's Bed", prompt: "a maple captain's bed, built-in drawers, white duvet as a thick slab, one pillow", category: .furniture),
        .init(title: "Eames Lounge", prompt: "an Eames-style lounge, rosewood shell, black leather cushions, ottoman as one piece", category: .furniture),
        .init(title: "Grandfather Clock", prompt: "a tall mahogany longcase clock, moon dial, brass pendulum visible as a disc, chunky case", category: .furniture),
        .init(title: "Upright Piano", prompt: "a black upright piano, closed fallboard, candlestick sconces as nubs, heavy legs", category: .furniture),
        .init(title: "Milking Stool", prompt: "a three-legged milking stool, thick round elm seat, splayed peg legs", category: .furniture),
        .init(title: "Rolltop Desk", prompt: "a closed oak rolltop desk, tambour down, cubby mass as one volume, brass pulls", category: .furniture),
        .init(title: "Club Chair", prompt: "a 1930s club chair, overstuffed cognac leather, low back, blocky silhouette", category: .furniture),
    ]

    // MARK: - Architecture

    static let architecture: [PromptPreset] = [
        .init(title: "Thatched Cottage", prompt: "a stone cottage, thick thatched roof, leaning chimney, tiny leaded windows as recesses", category: .architecture),
        .init(title: "Keep", prompt: "a compact Norman keep, pale ashlar, four corner turrets as one castle, arched gate", category: .architecture),
        .init(title: "Candy-Stripe Light", prompt: "a red-and-white candy-stripe lighthouse on a rock plinth, gallery railing as a ring", category: .architecture),
        .init(title: "Red Barn", prompt: "a New England barn, oxblood boards, white cross-buck doors, attached silo, chunky", category: .architecture),
        .init(title: "Igloo", prompt: "a snow igloo, spiral block dome, low tunnel entrance, compact closed volume", category: .architecture),
        .init(title: "Five-Story Pagoda", prompt: "a five-tier Japanese pagoda, vermilion and gold, deep eaves as thick slabs, compact", category: .architecture),
        .init(title: "Dutch Mill", prompt: "a Dutch smock mill, brick base, four sails as thick vanes, cap rotated, chunky", category: .architecture),
        .init(title: "Step Pyramid", prompt: "a stepped limestone pyramid, three terraces, sandy ochre, closed geometric mass", category: .architecture),
        .init(title: "Log Cabin", prompt: "a log cabin, saddle-notched corners, stone chimney, shallow porch as a slab", category: .architecture),
        .init(title: "Art Deco Tower", prompt: "an art-deco skyscraper, stepped setbacks, limestone and bronze, compact toy scale", category: .architecture),
        .init(title: "Roman Arch", prompt: "a Roman stone arch bridge, three arches as thick piers, weathered travertine", category: .architecture),
        .init(title: "Treehouse", prompt: "a plank treehouse hugging a thick oak trunk, peaked roof, round window, one volume", category: .architecture),
        .init(title: "Trullo", prompt: "an Apulian trullo, white cone roof, thick limewashed cylinder, tiny door recess", category: .architecture),
        .init(title: "Observatory Dome", prompt: "a white observatory dome, slit open, brick drum base, compact closed form", category: .architecture),
    ]

    // MARK: - Nature

    static let nature: [PromptPreset] = [
        .init(title: "Veteran Oak", prompt: "an ancient oak, massive trunk, short heavy boughs, closed green canopy as one volume", category: .nature),
        .init(title: "Cascade Bonsai", prompt: "a cascade bonsai in a glazed oval pot, twisted trunk, compact pad of foliage", category: .nature),
        .init(title: "Toadstool", prompt: "a red Amanita toadstool, white spots, thick stem, closed chunky cap", category: .nature),
        .init(title: "Saguaro", prompt: "a saguaro cactus, two arms, ribbed green column, closed silhouette", category: .nature),
        .init(title: "Cabbage Rose", prompt: "a cabbage rose bloom, many layered petals as a dense sphere, short leafy calyx", category: .nature),
        .init(title: "Sugar Pine Cone", prompt: "a large sugar-pine cone, open woody scales, oblong, resin-brown", category: .nature),
        .init(title: "Amethyst Geode", prompt: "a split amethyst geode, crystal cavity, rough rind, chunky half-sphere", category: .nature),
        .init(title: "Nautilus", prompt: "a chambered nautilus shell, logarithmic spiral, pearlescent cream and rust", category: .nature),
        .init(title: "Matterhorn", prompt: "a Matterhorn-like peak, snow cap, dark rock, closed pyramidal mass", category: .nature),
        .init(title: "Brain Coral", prompt: "a brain-coral head, meandering grooves, creamy mound, fully closed volume", category: .nature),
        .init(title: "Baobab", prompt: "a fat baobab, swollen trunk, sparse crown as a small pad, savannah silhouette", category: .nature),
        .init(title: "Driftwood", prompt: "a piece of silver driftwood, twisted, water-worn, compact closed knot", category: .nature),
    ]

    // MARK: - Food

    static let food: [PromptPreset] = [
        .init(title: "Smash Burger", prompt: "a smash cheeseburger, sesame bun, melted cheddar skirt, pickle, thick round stack", category: .food),
        .init(title: "Pepperoni Slice", prompt: "a New York pepperoni slice, blistered spots, folded tip, thick crust, on nothing", category: .food),
        .init(title: "Neapolitan Cone", prompt: "a waffle cone with three scoops, chocolate vanilla strawberry, chunky stack", category: .food),
        .init(title: "Diner Mug", prompt: "a heavy white diner mug, thick handle, coffee as a dark disc at the rim", category: .food),
        .init(title: "Honeycrisp", prompt: "a honeycrisp apple, speckled red-gold skin, short stem, one leaf, closed sphere", category: .food),
        .init(title: "Layer Cake", prompt: "a two-layer chocolate cake, ganache drip, round, closed, no thin candles", category: .food),
        .init(title: "Yeast Donut", prompt: "a yeast donut, pink icing, rainbow sprinkles as color, fat torus", category: .food),
        .init(title: "Nigiri Pair", prompt: "two salmon nigiri as one chunky pair, glossy fish, rice, no plate", category: .food),
        .init(title: "Bordeaux Bottle", prompt: "a dark-green Bordeaux bottle, foil capsule, recessed punt, closed cork", category: .food),
        .init(title: "Butter Croissant", prompt: "a butter croissant, deep lamination, crescent, golden, closed pastry volume", category: .food),
        .init(title: "Cast-Iron Loaf", prompt: "a country sourdough boule, flour-dusted ear, blistered crust, round closed loaf", category: .food),
        .init(title: "Matcha Bowl", prompt: "a raku matcha bowl, chawan, thick walls, green foam disc, irregular clay", category: .food),
        .init(title: "Wheel of Cheese", prompt: "a wheel of aged gouda, waxed rind, wedge cut showing interior, chunky disc", category: .food),
        .init(title: "Teapot Cake", prompt: "a brown betty teapot as pastry, glossy chocolate glaze, chunky ceramic-cake hybrid", category: .food),
    ]

    // MARK: - Props / Everyday

    static let props: [PromptPreset] = [
        .init(title: "Rangefinder", prompt: "a 1950s rangefinder camera, chrome top plate, black body, fat collapsible lens", category: .props),
        .init(title: "Dreadnought Guitar", prompt: "a dreadnought acoustic guitar, spruce top, tortoiseshell pickguard, chunky body", category: .props),
        .init(title: "Bakelite Phone", prompt: "a 1940s bakelite desk phone, round rotary dial, heavy handset in the cradle", category: .props),
        .init(title: "Field Watch", prompt: "a field watch, pancake case, canvas strap as a thick band, lumed numerals", category: .props),
        .init(title: "Alpine Pack", prompt: "an alpine backpack, olive canvas, bedroll on top, closed flap, chunky volume", category: .props),
        .init(title: "Golf Umbrella", prompt: "an open red golf umbrella, thick shaft, eight-panel canopy as a shallow dome", category: .props),
        .init(title: "Skate Helmet", prompt: "a skate helmet, gloss blue, thick foam, closed vents as recesses, round", category: .props),
        .init(title: "Brown Betty", prompt: "a brown betty teapot, rockingham glaze, round belly, short spout, chunky", category: .props),
        .init(title: "Railroad Lantern", prompt: "a railroad lantern, red glass globe, wire cage, kerosene fount, iron bail", category: .props),
        .init(title: "Loving Cup", prompt: "a two-handled silver loving cup trophy, wood plinth, closed bowl, chunky", category: .props),
        .init(title: "Casino Dice", prompt: "a pair of oversized casino dice fused as one piece, sharp pips, ivory", category: .props),
        .init(title: "Speed Cube", prompt: "a 3x3 speed cube, bright stickers as color, slightly rounded, closed cube", category: .props),
        .init(title: "Polaroid", prompt: "a vintage folding Polaroid, bellows as a thick wedge, chrome, tan leatherette", category: .props),
        .init(title: "Gramophone", prompt: "a wind-up gramophone, morning-glory horn, wooden case, closed disc on the platter", category: .props),
        .init(title: "Diving Helmet", prompt: "a copper three-bolt diving helmet, round viewports, closed collar, chunky", category: .props),
    ]

    // MARK: - Fantasy

    static let fantasy: [PromptPreset] = [
        .init(title: "Wyrmling", prompt: "a sitting green wyrmling, wings folded into the body, curled tail, closed chubby dragon", category: .fantasy),
        .init(title: "Unicorn", prompt: "a white unicorn standing, gold spiral horn, heavy mane as a closed mass, cloven hooves", category: .fantasy),
        .init(title: "Hoard Chest", prompt: "a closed iron-banded treasure chest, slight gold glow at the seam, chunky oak", category: .fantasy),
        .init(title: "Nightshade Phial", prompt: "a squat potion phial, glowing violet liquor, wax-dipped cork, thick glass", category: .fantasy),
        .init(title: "Seer's Orb", prompt: "a crystal ball on a three-clawed bronze stand, inner swirl of smoke as color", category: .fantasy),
        .init(title: "Sword in the Stone", prompt: "an anvil-stone with a jeweled sword buried to the hilt, one closed legendary volume", category: .fantasy),
        .init(title: "Phoenix", prompt: "a phoenix perched, fire plumage as a closed teardrop of red-gold feathers, compact", category: .fantasy),
        .init(title: "Toadstool Cottage", prompt: "a fairy house built into a red toadstool, round door, mossy cap, one closed dwelling", category: .fantasy),
        .init(title: "Grimoire", prompt: "a closed leather grimoire, iron clasps, gem in the cover, thick yellowed block", category: .fantasy),
        .init(title: "Rune Golem", prompt: "a rune-carved stone golem standing, moss in the joints, glowing glyph cracks", category: .fantasy),
        .init(title: "Dragon Egg", prompt: "a dragon egg, scaled shell, gold-green, sitting in a stone nest as one piece", category: .fantasy),
        .init(title: "Portal Arch", prompt: "a standing stone portal, two megaliths and a lintel as one dolmen, inner glow", category: .fantasy),
        .init(title: "Kraken Bell", prompt: "a bronze ship's bell with octopus relief, heavy clapper as a nub, verdigris", category: .fantasy),
        .init(title: "Moon Staff", prompt: "a wizard's staff as a thick gnarled trunk, crystal head as a closed orb, no thin twigs", category: .fantasy),
    ]

    // MARK: - Abstract / Forms

    static let abstract: [PromptPreset] = [
        .init(title: "Torus Knot", prompt: "a (3,2) torus knot, tubular, closed, brushed cobalt, sculpture scale", category: .abstract),
        .init(title: "Icosahedron", prompt: "a regular icosahedron, matte bone, sharp edges slightly rounded, solid", category: .abstract),
        .init(title: "Möbius", prompt: "a thick Möbius band, orange anodized, generous tube radius, closed loop", category: .abstract),
        .init(title: "Log Spiral", prompt: "an abstract logarithmic spiral, pearlescent, growing tube, closed sculpture", category: .abstract),
        .init(title: "Metaball", prompt: "a smooth three-lobe metaball, pastel blush, high-gloss, closed organic", category: .abstract),
        .init(title: "Low-Poly Bust", prompt: "a low-poly human head bust, faceted gray, truncated neck as a solid plinth", category: .abstract),
        .init(title: "Double Helix", prompt: "a chunky double helix, two thick strands, blue and coral, closed sculpture", category: .abstract),
        .init(title: "Spur Gear", prompt: "a machined spur gear, thick face width, involute teeth, steel, closed disc", category: .abstract),
        .init(title: "Gyroid Chunk", prompt: "a cubic gyroid lattice chunk, thick walls, bronze, closed bounding cube", category: .abstract),
        .init(title: "Klein Bottle", prompt: "a Klein bottle, fat tube, self-intersection as a closed glass form, teal", category: .abstract),
        .init(title: "Archimedean Spiral", prompt: "an Archimedean spiral disc, raised ridge, matte white, pancake sculpture", category: .abstract),
        .init(title: "Boolean Rock", prompt: "a rock subtracted by three spheres, concrete gray, sharp boolean edges, closed", category: .abstract),
    ]
}
