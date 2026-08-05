import KeypressCore

// MARK: - MarketingLocale

/// The App Store locales the marketing media is rendered in. Russian is last,
/// the way every language list in the product enumerates them.
enum MarketingLocale: String, CaseIterable {
    case enUS = "en-US"
    case deDE = "de-DE"
    case esES = "es-ES"
    case frFR = "fr-FR"
    case ru

    /// Drives the UI language of the settings window captured into frames 07/08.
    var appLanguage: AppLanguage {
        switch self {
        case .enUS: .english
        case .deDE: .german
        case .esES: .spanish
        case .frFR: .french
        case .ru: .russian
        }
    }
}

// MARK: - SceneCopy

/// The header block of one frame: mono kicker, serif headline whose single
/// `*word*` renders as the accent, and the benefit sentence under it.
struct SceneCopy {
    let kicker: String
    let headline: String
    let subline: String
}

// MARK: - MarketingStrings

/// Every translated string of the store frames, one table per locale.
///
/// Deliberately English everywhere: the brand row, the theme names, the staged
/// window titles and the language chips — product vocabulary that reads the same
/// in every listing.
struct MarketingStrings {
    let hero: SceneCopy
    let cursorHalo: SceneCopy
    let pet: SceneCopy
    let themes: SceneCopy
    let stackedHistory: SceneCopy
    let placement: SceneCopy
    let studio: SceneCopy
    let studioAppearance: SceneCopy
    let languages: SceneCopy
    let privacy: SceneCopy
    /// Pet habits: sleeps, hunts the cursor, stretches, plays.
    let petChips: [String]
    /// Halo tiles: circle, squircle, square, diamond.
    let haloVariants: [String]
    let themesFootnote: String
    /// Display plates: the dragged main display, then the external one.
    let placementCaptions: [String]
    let placementChips: [String]
    let privacyPills: [String]
    let privacyWindowTitle: String
    let privacyFieldLabel: String
    let privacyBadge: String

    static func table(for locale: MarketingLocale) -> MarketingStrings {
        switch locale {
        case .enUS: self.english
        case .deDE: self.german
        case .esES: self.spanish
        case .frFR: self.french
        case .ru: self.russian
        }
    }

    func copy(for id: SceneID) -> SceneCopy {
        switch id {
        case .hero: self.hero
        case .cursorHalo: self.cursorHalo
        case .pet: self.pet
        case .themes: self.themes
        case .stackedHistory: self.stackedHistory
        case .placement: self.placement
        case .studio: self.studio
        case .studioAppearance: self.studioAppearance
        case .languages: self.languages
        case .privacy: self.privacy
        }
    }

    static let english = MarketingStrings(
        hero: SceneCopy(
            kicker: "Live input overlay for macOS",
            headline: "Every *keystroke*, on screen.",
            subline: "Real mechanical keycaps, a glowing cursor halo and a typing cat — "
                + "built for screen shares, streams and tutorials."),
        cursorHalo: SceneCopy(
            kicker: "Cursor halo",
            headline: "Never lose the *pointer* again.",
            subline: "Shapes, glow and distinct reactions to clicks, drags and scrolls. "
                + "Your viewers always know where the action is."),
        pet: SceneCopy(
            kicker: "Keypress pet",
            headline: "A *cat* that types with you.",
            subline: "It types at your speed, watches the cursor and naps when you rest. "
                + "Every habit has its own switch."),
        themes: SceneCopy(
            kicker: "Themes",
            headline: "Nine looks. Or build your *own*.",
            subline: "Nine built-in families for keyboard and pointer — "
                + "or design your own, down to per-key colors."),
        stackedHistory: SceneCopy(
            kicker: "Stacked history",
            headline: "Typing your viewers can *read*.",
            subline: "Continuous typing folds into readable lines "
                + "while the active shortcut stays anchored."),
        placement: SceneCopy(
            kicker: "Displays & position",
            headline: "Exactly where it *belongs*.",
            subline: "Drag the real overlay on any display — "
                + "with snapping, guides and a saved spot per screen."),
        studio: SceneCopy(
            kicker: "Native settings",
            headline: "A *studio*, not a settings sheet.",
            subline: "Live previews, theme galleries and per-behavior controls "
                + "in a native sidebar interface."),
        studioAppearance: SceneCopy(
            kicker: "Keyboard appearance",
            headline: "Tune every *key*.",
            subline: "Materials, press effects, fonts and per-category colors — "
                + "with a live preview pinned on top."),
        languages: SceneCopy(
            kicker: "Five languages",
            headline: "Speaks your *language*.",
            subline: "Keys come from your active layout — "
                + "accents, umlauts and Cyrillic show exactly what you typed."),
        privacy: SceneCopy(
            kicker: "Private by design",
            headline: "Nothing *leaves* your Mac.",
            subline: "Keystrokes are drawn, then forgotten. "
                + "Passwords stay hidden while macOS Secure Input is active."),
        petChips: ["sleeps", "hunts the cursor", "stretches", "plays"],
        haloVariants: ["circle · aura", "squircle · neon depth", "square · solid", "diamond · segmented"],
        themesFootnote: "+ custom editor · fonts · colors · depth · corners · shadows",
        placementCaptions: ["main display · dragging", "external · saved position"],
        placementChips: ["drag anywhere", "snapping", "per-display"],
        privacyPills: ["no storage", "no network", "secure input aware"],
        privacyWindowTitle: "sign in — account",
        privacyFieldLabel: "Password",
        privacyBadge: "SECURE INPUT · OVERLAY PAUSED")

    static let german = MarketingStrings(
        hero: SceneCopy(
            kicker: "Live-Overlay für macOS",
            headline: "Jeder *Tastendruck* — auf dem Bildschirm.",
            subline: "Echte mechanische Tastenkappen, ein leuchtender Cursor-Halo und eine tippende Katze — "
                + "für Screensharing, Streams und Tutorials."),
        cursorHalo: SceneCopy(
            kicker: "Cursor-Halo",
            headline: "Den *Zeiger* nie wieder verlieren.",
            subline: "Formen, Leuchten und eigene Reaktionen auf Klicks, Ziehen und Scrollen. "
                + "Dein Publikum weiß immer, wo etwas passiert."),
        pet: SceneCopy(
            kicker: "Keypress-Haustier",
            headline: "Eine *Katze*, die mittippt.",
            subline: "Sie tippt in deinem Tempo, beobachtet den Zeiger und döst, wenn du pausierst. "
                + "Jede Gewohnheit hat ihren eigenen Schalter."),
        themes: SceneCopy(
            kicker: "Themes",
            headline: "Neun Looks. Oder dein *eigener*.",
            subline: "Neun eingebaute Familien für Tastatur und Zeiger — "
                + "oder gestalte deine eigene, bis zur Farbe jeder Taste."),
        stackedHistory: SceneCopy(
            kicker: "Gestapelter Verlauf",
            headline: "Tippen, das man *lesen* kann.",
            subline: "Fortlaufendes Tippen faltet sich zu lesbaren Zeilen, "
                + "während der aktive Kurzbefehl verankert bleibt."),
        placement: SceneCopy(
            kicker: "Displays & Position",
            headline: "Genau dort, wo es *hingehört*.",
            subline: "Zieh das echte Overlay auf jedem Display — "
                + "mit Einrasten, Hilfslinien und gespeicherter Position pro Bildschirm."),
        studio: SceneCopy(
            kicker: "Native Einstellungen",
            headline: "Ein *Studio*, kein Einstellungsfenster.",
            subline: "Live-Vorschauen, Themen-Galerien und feine Schalter "
                + "in einer nativen Seitenleisten-Oberfläche."),
        studioAppearance: SceneCopy(
            kicker: "Tastatur-Look",
            headline: "Jede *Taste* fein abstimmen.",
            subline: "Materialien, Druck-Effekte, Schriften und Farben pro Kategorie — "
                + "mit angehefteter Live-Vorschau."),
        languages: SceneCopy(
            kicker: "Fünf Sprachen",
            headline: "Spricht deine *Sprache*.",
            subline: "Tasten kommen aus deiner aktiven Belegung — "
                + "Akzente, Umlaute und Kyrillisch zeigen genau, was du getippt hast."),
        privacy: SceneCopy(
            kicker: "Privatsphäre eingebaut",
            headline: "Nichts *verlässt* deinen Mac.",
            subline: "Anschläge werden gezeichnet und vergessen. "
                + "Passwörter bleiben verborgen, solange die sichere Eingabe von macOS aktiv ist."),
        petChips: ["schläft", "jagt den Zeiger", "streckt sich", "spielt"],
        haloVariants: ["Kreis · Aura", "Squircle · Neontiefe", "Quadrat · Solid", "Raute · Segmente"],
        themesFootnote: "+ eigener Editor · Schriften · Farben · Tiefe · Ecken · Schatten",
        placementCaptions: ["Hauptdisplay · Ziehen", "Extern · gespeicherte Position"],
        placementChips: ["frei ziehen", "Einrasten", "pro Display"],
        privacyPills: ["keine Speicherung", "kein Netzwerk", "sichere Eingabe erkannt"],
        privacyWindowTitle: "Anmelden — Account",
        privacyFieldLabel: "Passwort",
        privacyBadge: "SICHERE EINGABE · OVERLAY PAUSIERT")

    static let spanish = MarketingStrings(
        hero: SceneCopy(
            kicker: "Overlay de entrada para macOS",
            headline: "Cada *pulsación*, en pantalla.",
            subline: "Teclas mecánicas reales, un halo de cursor luminoso y un gato que teclea: "
                + "para compartir pantalla, streams y tutoriales."),
        cursorHalo: SceneCopy(
            kicker: "Halo del cursor",
            headline: "No pierdas más el *puntero*.",
            subline: "Formas, brillo y reacciones distintas a clics, arrastres y desplazamiento. "
                + "Tu audiencia siempre sabe dónde está la acción."),
        pet: SceneCopy(
            kicker: "Mascota Keypress",
            headline: "Un *gato* que teclea contigo.",
            subline: "Teclea a tu ritmo, vigila el cursor y dormita cuando descansas. "
                + "Cada hábito tiene su propio interruptor."),
        themes: SceneCopy(
            kicker: "Temas",
            headline: "Nueve estilos. O crea el *tuyo*.",
            subline: "Nueve familias integradas para teclado y puntero, "
                + "o diseña la tuya hasta el color de cada tecla."),
        stackedHistory: SceneCopy(
            kicker: "Historial apilado",
            headline: "Escritura que se puede *leer*.",
            subline: "La escritura continua se pliega en líneas legibles "
                + "mientras el atajo activo queda anclado."),
        placement: SceneCopy(
            kicker: "Pantallas y posición",
            headline: "Justo donde *debe* estar.",
            subline: "Arrastra el overlay real en cualquier pantalla: "
                + "con imán, guías y posición guardada por pantalla."),
        studio: SceneCopy(
            kicker: "Ajustes nativos",
            headline: "Un *estudio*, no una hoja de ajustes.",
            subline: "Vistas previas en vivo, galerías de temas y controles por comportamiento "
                + "en una interfaz nativa con barra lateral."),
        studioAppearance: SceneCopy(
            kicker: "Aspecto del teclado",
            headline: "Ajusta cada *tecla*.",
            subline: "Materiales, efectos de pulsación, tipografías y colores por categoría, "
                + "con vista previa fija arriba."),
        languages: SceneCopy(
            kicker: "Cinco idiomas",
            headline: "Habla tu *idioma*.",
            subline: "Las teclas salen de tu distribución activa: "
                + "acentos, diéresis y cirílico muestran justo lo que escribiste."),
        privacy: SceneCopy(
            kicker: "Privado por diseño",
            headline: "Nada *sale* de tu Mac.",
            subline: "Las pulsaciones se dibujan y se olvidan. "
                + "Las contraseñas quedan ocultas mientras la entrada segura de macOS está activa."),
        petChips: ["duerme", "caza el cursor", "se estira", "juega"],
        haloVariants: ["círculo · aura", "squircle · neón", "cuadrado · sólido", "rombo · segmentos"],
        themesFootnote: "+ editor propio · tipografías · colores · profundidad · esquinas · sombras",
        placementCaptions: ["pantalla principal · arrastrando", "externa · posición guardada"],
        placementChips: ["arrastra libre", "imán", "por pantalla"],
        privacyPills: ["sin guardar", "sin red", "detecta entrada segura"],
        privacyWindowTitle: "inicio de sesión — cuenta",
        privacyFieldLabel: "Contraseña",
        privacyBadge: "ENTRADA SEGURA · OVERLAY EN PAUSA")

    static let french = MarketingStrings(
        hero: SceneCopy(
            kicker: "Overlay de saisie pour macOS",
            headline: "Chaque *frappe*, à l'écran.",
            subline: "De vraies touches mécaniques, un halo de curseur lumineux et un chat qui tape — "
                + "pour partages d'écran, streams et tutoriels."),
        cursorHalo: SceneCopy(
            kicker: "Halo du curseur",
            headline: "Ne perdez plus le *curseur*.",
            subline: "Formes, halo lumineux et réactions distinctes aux clics, glissements et défilements. "
                + "Votre audience sait toujours où se passe l'action."),
        pet: SceneCopy(
            kicker: "Mascotte Keypress",
            headline: "Un *chat* qui tape avec vous.",
            subline: "Il tape à votre rythme, surveille le curseur et somnole quand vous faites une pause. "
                + "Chaque habitude a son interrupteur."),
        themes: SceneCopy(
            kicker: "Thèmes",
            headline: "Neuf styles. Ou le *vôtre*.",
            subline: "Neuf familles intégrées pour clavier et pointeur — "
                + "ou créez la vôtre, jusqu'à la couleur de chaque touche."),
        stackedHistory: SceneCopy(
            kicker: "Historique empilé",
            headline: "Une frappe qu'on peut *lire*.",
            subline: "La saisie continue se replie en lignes lisibles, "
                + "le raccourci actif restant ancré."),
        placement: SceneCopy(
            kicker: "Écrans et position",
            headline: "Exactement à sa *place*.",
            subline: "Glissez le vrai overlay sur n'importe quel écran — "
                + "aimantation, guides et position mémorisée par écran."),
        studio: SceneCopy(
            kicker: "Réglages natifs",
            headline: "Un *studio*, pas une fiche de réglages.",
            subline: "Aperçus en direct, galeries de thèmes et réglages par comportement "
                + "dans une interface native à barre latérale."),
        studioAppearance: SceneCopy(
            kicker: "Apparence du clavier",
            headline: "Réglez chaque *touche*.",
            subline: "Matériaux, effets de frappe, polices et couleurs par catégorie — "
                + "avec aperçu en direct épinglé."),
        languages: SceneCopy(
            kicker: "Cinq langues",
            headline: "Parle votre *langue*.",
            subline: "Les touches suivent votre disposition active — "
                + "accents, trémas et cyrillique affichent exactement ce que vous avez tapé."),
        privacy: SceneCopy(
            kicker: "Privé par conception",
            headline: "Rien ne *quitte* votre Mac.",
            subline: "Les frappes sont dessinées puis oubliées. "
                + "Les mots de passe restent masqués tant que la saisie sécurisée de macOS est active."),
        petChips: ["dort", "chasse le curseur", "s'étire", "joue"],
        haloVariants: ["cercle · aura", "squircle · néon", "carré · plein", "losange · segments"],
        themesFootnote: "+ éditeur perso · polices · couleurs · profondeur · coins · ombres",
        placementCaptions: ["écran principal · glissement", "externe · position mémorisée"],
        placementChips: ["glisser partout", "aimantation", "par écran"],
        privacyPills: ["aucun stockage", "aucun réseau", "saisie sécurisée détectée"],
        privacyWindowTitle: "connexion — compte",
        privacyFieldLabel: "Mot de passe",
        privacyBadge: "SAISIE SÉCURISÉE · OVERLAY EN PAUSE")

    static let russian = MarketingStrings(
        hero: SceneCopy(
            kicker: "Оверлей ввода для macOS",
            headline: "Каждое *нажатие* — на экране.",
            subline: "Настоящие механические клавиши, подсветка курсора и печатающий кот — "
                + "для демонстраций экрана, стримов и туториалов."),
        cursorHalo: SceneCopy(
            kicker: "Подсветка курсора",
            headline: "Курсор больше не *теряется*.",
            subline: "Формы, свечение и отдельные реакции на клики, перетаскивание и прокрутку. "
                + "Зрители всегда видят, где действие."),
        pet: SceneCopy(
            kicker: "Питомец Keypress",
            headline: "*Кот*, который печатает с вами.",
            subline: "Печатает в вашем темпе, следит за курсором и дремлет, когда вы отдыхаете. "
                + "У каждой повадки свой переключатель."),
        themes: SceneCopy(
            kicker: "Темы",
            headline: "Девять образов. Или *свой*.",
            subline: "Девять встроенных семейств для клавиатуры и указателя — "
                + "или соберите собственное, вплоть до цвета каждой клавиши."),
        stackedHistory: SceneCopy(
            kicker: "История стопкой",
            headline: "Набор, который можно *прочитать*.",
            subline: "Непрерывная печать складывается в читаемые строки, "
                + "а активное сочетание остаётся на месте."),
        placement: SceneCopy(
            kicker: "Дисплеи и позиция",
            headline: "Ровно там, где *нужно*.",
            subline: "Перетащите настоящий оверлей на любом дисплее — "
                + "с привязкой, направляющими и памятью позиции для каждого экрана."),
        studio: SceneCopy(
            kicker: "Нативные настройки",
            headline: "*Студия*, а не окно настроек.",
            subline: "Живые превью, галереи тем и точные переключатели "
                + "в нативном интерфейсе с сайдбаром."),
        studioAppearance: SceneCopy(
            kicker: "Оформление клавиатуры",
            headline: "Настройте каждую *клавишу*.",
            subline: "Материалы, эффекты нажатия, шрифты и цвета по категориям — "
                + "с закреплённым живым превью."),
        languages: SceneCopy(
            kicker: "Пять языков",
            headline: "Говорит на вашем *языке*.",
            subline: "Клавиши берутся из активной раскладки — "
                + "акценты, умляуты и кириллица показывают именно то, что вы набрали."),
        privacy: SceneCopy(
            kicker: "Приватность по умолчанию",
            headline: "Ничего не *покидает* ваш Mac.",
            subline: "Нажатия рисуются и забываются. "
                + "Пароли скрыты, пока активен безопасный ввод macOS."),
        petChips: ["спит", "охотится за курсором", "потягивается", "играет"],
        haloVariants: ["круг · аура", "скруглённый · неон", "квадрат · сплошной", "ромб · сегменты"],
        themesFootnote: "+ свой редактор · шрифты · цвета · глубина · углы · тени",
        placementCaptions: ["основной дисплей · перетаскивание", "внешний · сохранённая позиция"],
        placementChips: ["куда угодно", "привязка", "для каждого дисплея"],
        privacyPills: ["без записи", "без сети", "учитывает безопасный ввод"],
        privacyWindowTitle: "вход — аккаунт",
        privacyFieldLabel: "Пароль",
        privacyBadge: "БЕЗОПАСНЫЙ ВВОД · ОВЕРЛЕЙ НА ПАУЗЕ")
}
