import Foundation

/// UI languages the interface can be displayed in (independent of translation languages).
enum UILanguage: String, CaseIterable, Identifiable, Codable {
    case en, ru, de, es, fr, it, pt
    var id: String { rawValue }

    /// Native name shown in the interface-language picker.
    var endonym: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .fr: return "Français"
        case .it: return "Italiano"
        case .pt: return "Português"
        }
    }
}

/// Localization keys. Every user-facing string in the UI goes through here.
enum LKey: String {
    // Header / sections
    case settingsTitle
    case secLicense, secApp, secVoice, secPermissions, secAPI, secTheme, secUpdates
    // App settings
    case launchAtLogin, showMenuBarIcon, openBabelBar, translateAuto, translateScreenshot
    // Updates
    case autoCheckUpdates, checkForUpdatesNow, checkingUpdates, lastChecked, neverChecked
    case updateUpToDate, updateAvailableFmt, updateFailed, updateDownload
    // GitHub star card
    case githubStar, recentlyStarred, starsWord
    case languagePreferences, interfaceLanguage, source, target, autoDetect
    // Voice
    case dictateToCursor, triggerSound, showRecordingDot, duckAudio
    // Permissions
    case permAccessibility, permInput, permScreen, permMic, permSpeech
    case granted, openSettings
    // API
    case apiPrimary, apiSecondary, addFallback, provider, baseURL, model, apiKey
    case tokensUsed, used, tokensWord, aiInstructions
    case saveChanges, resetDefaults, resetConfirm, cancel
    // License
    case activated, freeTrial, trialEnded, enterLicenseKey, activate, daysLeftFmt
    // Translator screen
    case inputPlaceholder, dictatingPlaceholder, outputPlaceholder, translatingPlaceholder
    case clear, voiceInputTip, forQuickCopy, insertTranslation
    case recordKeys, recordModifiers
    // Errors & status-bar menu
    case errMicSpeech, menuShow, menuSettings, menuQuit
    // Speech engine section
    case secSpeech, recognition, engineLocal, engineRemote
    case download, downloading, modelReady, downloaded, initializing, insertion, insertPaste, insertType
    case remoteNote
    case tipSpeechEngine, tipModelDownload, tipInsertMethod
    // API status
    case apiOffline, apiNoTokens, apiOnline
    // Tooltips
    case tipOpen, tipTranslateAuto, tipScreenshot, tipDictate, tipAIInstructions
    case tipShowRecordingDot, tipDuckAudio
}

enum Loc {
    /// Column order for every row below: en, ru, de, es, fr, it, pt.
    private static let order: [UILanguage] = [.en, .ru, .de, .es, .fr, .it, .pt]

    static func t(_ key: LKey, _ lang: UILanguage) -> String {
        guard let row = table[key], let i = order.firstIndex(of: lang), i < row.count else {
            return table[key]?.first ?? key.rawValue
        }
        return row[i]
    }

    private static func r(_ en: String, _ ru: String, _ de: String, _ es: String,
                          _ fr: String, _ it: String, _ pt: String) -> [String] {
        [en, ru, de, es, fr, it, pt]
    }

    private static let table: [LKey: [String]] = [
        .settingsTitle: r("BabelBar Settings", "Настройки BabelBar", "BabelBar-Einstellungen",
                          "Ajustes de BabelBar", "Réglages BabelBar", "Impostazioni BabelBar", "Configurações do BabelBar"),

        // Section headers (shown uppercased by the view's styling)
        .secLicense: r("License", "Лицензия", "Lizenz", "Licencia", "Licence", "Licenza", "Licença"),
        .secApp: r("App Settings", "Настройки приложения", "App-Einstellungen", "Ajustes de la app",
                   "Réglages de l’app", "Impostazioni app", "Configurações do app"),
        .secVoice: r("Voice Input", "Голосовой ввод", "Spracheingabe", "Entrada de voz",
                     "Saisie vocale", "Input vocale", "Entrada de voz"),
        .secPermissions: r("Permissions", "Разрешения", "Berechtigungen", "Permisos",
                           "Autorisations", "Autorizzazioni", "Permissões"),
        .secAPI: r("API Settings", "Настройки API", "API-Einstellungen", "Ajustes de API",
                   "Réglages API", "Impostazioni API", "Configurações da API"),
        .secTheme: r("Theme", "Тема", "Design", "Tema", "Thème", "Tema", "Tema"),
        .secUpdates: r("Updates", "Обновления", "Updates", "Actualizaciones", "Mises à jour", "Aggiornamenti", "Atualizações"),

        // App settings — menu bar
        .showMenuBarIcon: r("Show menu bar icon", "Показывать значок в строке меню", "Symbol in der Menüleiste anzeigen",
                           "Mostrar icono en la barra de menús", "Afficher l’icône dans la barre des menus",
                           "Mostra icona nella barra dei menu", "Mostrar ícone na barra de menus"),

        // Updates
        .autoCheckUpdates: r("Automatically check for updates", "Автоматически проверять обновления",
                            "Automatisch nach Updates suchen", "Buscar actualizaciones automáticamente",
                            "Rechercher les mises à jour automatiquement", "Controlla aggiornamenti automaticamente",
                            "Verificar atualizações automaticamente"),
        .checkForUpdatesNow: r("Check for Updates Now", "Проверить обновления", "Jetzt nach Updates suchen",
                              "Buscar actualizaciones ahora", "Rechercher maintenant", "Controlla aggiornamenti ora",
                              "Verificar agora"),
        .checkingUpdates: r("Checking…", "Проверка…", "Suche…", "Buscando…", "Recherche…", "Controllo…", "Verificando…"),
        .lastChecked: r("Last checked", "Последняя проверка", "Zuletzt geprüft", "Última comprobación",
                       "Dernière vérification", "Ultimo controllo", "Última verificação"),
        .neverChecked: r("Never", "Никогда", "Nie", "Nunca", "Jamais", "Mai", "Nunca"),
        .updateUpToDate: r("You're up to date", "Установлена последняя версия", "Sie sind auf dem neuesten Stand",
                          "Estás al día", "Vous êtes à jour", "Sei aggiornato", "Você está atualizado"),
        .updateAvailableFmt: r("Version %@ available", "Доступна версия %@", "Version %@ verfügbar",
                              "Versión %@ disponible", "Version %@ disponible", "Versione %@ disponibile",
                              "Versão %@ disponível"),
        .updateFailed: r("Couldn't check for updates", "Не удалось проверить обновления",
                        "Suche nach Updates fehlgeschlagen", "No se pudo buscar actualizaciones",
                        "Échec de la recherche de mises à jour", "Impossibile controllare gli aggiornamenti",
                        "Não foi possível verificar atualizações"),
        .updateDownload: r("Download", "Скачать", "Herunterladen", "Descargar", "Télécharger", "Scarica", "Baixar"),

        // GitHub star card
        .githubStar: r("Star", "В избранное", "Star", "Estrella", "Star", "Star", "Star"),
        .recentlyStarred: r("recently starred", "недавно отметили", "kürzlich markiert",
                           "destacados recientemente", "récemment ajoutés", "aggiunti di recente",
                           "marcados recentemente"),
        .starsWord: r("stars", "звёзд", "Sterne", "estrellas", "étoiles", "stelle", "estrelas"),

        // App settings
        .launchAtLogin: r("Launch at login", "Запуск при входе", "Beim Anmelden starten", "Iniciar al iniciar sesión",
                          "Lancer à la connexion", "Avvia all’accesso", "Iniciar ao fazer login"),
        .openBabelBar: r("Open BabelBar", "Открыть BabelBar", "BabelBar öffnen", "Abrir BabelBar",
                         "Ouvrir BabelBar", "Apri BabelBar", "Abrir o BabelBar"),
        .translateAuto: r("Translate Automatically", "Переводить автоматически", "Automatisch übersetzen",
                          "Traducir automáticamente", "Traduire automatiquement", "Traduci automaticamente", "Traduzir automaticamente"),
        .translateScreenshot: r("Translate Screenshot", "Перевод скриншота", "Screenshot übersetzen",
                               "Traducir captura", "Traduire la capture", "Traduci screenshot", "Traduzir captura"),
        .languagePreferences: r("Language Preferences", "Языки перевода", "Sprachen", "Idiomas",
                               "Langues", "Lingue", "Idiomas"),
        .interfaceLanguage: r("Interface language", "Язык интерфейса", "Sprache der Oberfläche", "Idioma de la interfaz",
                             "Langue de l’interface", "Lingua dell’interfaccia", "Idioma da interface"),
        .source: r("Source", "Источник", "Quelle", "Origen", "Source", "Origine", "Origem"),
        .target: r("Target", "Цель", "Ziel", "Destino", "Cible", "Destinazione", "Destino"),
        .autoDetect: r("Auto", "Авто", "Auto", "Auto", "Auto", "Auto", "Auto"),

        // Voice
        .dictateToCursor: r("Dictate to cursor", "Диктовать под курсор", "An Cursor diktieren", "Dictar en el cursor",
                           "Dicter au curseur", "Detta al cursore", "Ditar no cursor"),
        .triggerSound: r("Trigger sound", "Звук запуска", "Auslöseton", "Sonido de activación",
                        "Son de déclenchement", "Suono di attivazione", "Som de ativação"),
        .showRecordingDot: r("Show recording indicator", "Показывать индикатор записи",
                            "Aufnahmeindikator anzeigen", "Mostrar indicador de grabación",
                            "Afficher l’indicateur d’enregistrement", "Mostra indicatore di registrazione",
                            "Mostrar indicador de gravação"),
        .duckAudio: r("Duck audio while dictating", "Приглушать звук при диктовке",
                     "Ton beim Diktieren dämpfen", "Bajar el audio al dictar",
                     "Atténuer le son pendant la dictée", "Abbassa l’audio durante la dettatura",
                     "Abaixar o áudio ao ditar"),

        // Permissions
        .permAccessibility: r("Accessibility", "Универсальный доступ", "Bedienungshilfen", "Accesibilidad",
                             "Accessibilité", "Accessibilità", "Acessibilidade"),
        .permInput: r("Input Monitoring", "Мониторинг ввода", "Eingabeüberwachung", "Monitorización de entrada",
                     "Surveillance des saisies", "Monitoraggio input", "Monitoramento de entrada"),
        .permScreen: r("Screen Recording", "Запись экрана", "Bildschirmaufnahme", "Grabación de pantalla",
                      "Enregistrement de l’écran", "Registrazione schermo", "Gravação de tela"),
        .permMic: r("Microphone", "Микрофон", "Mikrofon", "Micrófono", "Microphone", "Microfono", "Microfone"),
        .permSpeech: r("Speech Recognition", "Распознавание речи", "Spracherkennung", "Reconocimiento de voz",
                      "Reconnaissance vocale", "Riconoscimento vocale", "Reconhecimento de fala"),
        .granted: r("Granted", "Разрешено", "Erteilt", "Concedido", "Accordé", "Concesso", "Concedido"),
        .openSettings: r("Open Settings", "Открыть настройки", "Einstellungen öffnen", "Abrir ajustes",
                        "Ouvrir les réglages", "Apri impostazioni", "Abrir configurações"),

        // API
        .apiPrimary: r("Primary", "Основной", "Primär", "Principal", "Principal", "Primario", "Principal"),
        .apiSecondary: r("Secondary · Fallback", "Запасной · Fallback", "Sekundär · Fallback", "Secundario · Reserva",
                        "Secondaire · Secours", "Secondario · Fallback", "Secundário · Reserva"),
        .addFallback: r("Add fallback provider", "Добавить запасного провайдера", "Fallback-Anbieter hinzufügen",
                       "Añadir proveedor de reserva", "Ajouter un fournisseur de secours", "Aggiungi provider di riserva", "Adicionar provedor reserva"),
        .provider: r("Provider", "Провайдер", "Anbieter", "Proveedor", "Fournisseur", "Provider", "Provedor"),
        .baseURL: r("Base URL", "Базовый URL", "Basis-URL", "URL base", "URL de base", "URL base", "URL base"),
        .model: r("Model", "Модель", "Modell", "Modelo", "Modèle", "Modello", "Modelo"),
        .apiKey: r("API Key", "API-ключ", "API-Schlüssel", "Clave API", "Clé API", "Chiave API", "Chave de API"),
        .tokensUsed: r("Token status", "Токен статус", "Token-Status", "Estado de tokens",
                      "État des jetons", "Stato token", "Status do token"),
        .used: r("Used", "Исп.", "Verbraucht", "Usados", "Utilisés", "Usati", "Usados"),
        .tokensWord: r("tokens", "токенов", "Tokens", "tokens", "jetons", "token", "tokens"),
        .aiInstructions: r("AI Instructions", "Инструкции для ИИ", "KI-Anweisungen", "Instrucciones de IA",
                          "Instructions IA", "Istruzioni IA", "Instruções de IA"),
        .saveChanges: r("Save Changes", "Сохранить изменения", "Änderungen speichern", "Guardar cambios",
                       "Enregistrer les modifications", "Salva modifiche", "Salvar alterações"),
        .resetDefaults: r("reset to defaults", "reset to defaults", "reset to defaults", "reset to defaults",
                         "reset to defaults", "reset to defaults", "reset to defaults"),
        .resetConfirm: r("Reset all settings to factory defaults?",
                        "Сбросить все настройки до заводских?",
                        "Alle Einstellungen auf Werkseinstellungen zurücksetzen?",
                        "¿Restablecer todos los ajustes de fábrica?",
                        "Réinitialiser tous les réglages aux valeurs d’usine ?",
                        "Ripristinare tutte le impostazioni di fabbrica?",
                        "Redefinir todas as configurações de fábrica?"),
        .cancel: r("Cancel", "Отмена", "Abbrechen", "Cancelar", "Annuler", "Annulla", "Cancelar"),

        // License
        .activated: r("Activated", "Активировано", "Aktiviert", "Activado", "Activé", "Attivato", "Ativado"),
        .freeTrial: r("Free trial", "Пробный период", "Kostenlose Testphase", "Prueba gratuita",
                     "Essai gratuit", "Prova gratuita", "Avaliação gratuita"),
        .trialEnded: r("Trial ended — enter a key to continue.", "Пробный период закончился — введите ключ, чтобы продолжить.",
                      "Testphase beendet — Schlüssel eingeben, um fortzufahren.", "La prueba terminó — introduce una clave para continuar.",
                      "Essai terminé — saisissez une clé pour continuer.", "Prova terminata — inserisci una chiave per continuare.",
                      "Avaliação encerrada — insira uma chave para continuar."),
        .enterLicenseKey: r("Enter license key", "Введите ключ лицензии", "Lizenzschlüssel eingeben", "Introduce la clave de licencia",
                           "Saisissez la clé de licence", "Inserisci la chiave di licenza", "Insira a chave de licença"),
        .activate: r("Activate", "Активировать", "Aktivieren", "Activar", "Activer", "Attiva", "Ativar"),
        .daysLeftFmt: r("%d days left", "Осталось дней: %d", "%d Tage übrig", "%d días restantes",
                       "%d jours restants", "%d giorni rimasti", "%d dias restantes"),

        // Translator screen
        .inputPlaceholder: r("Enter text to translate...", "Введите текст для перевода...", "Text zum Übersetzen eingeben...",
                            "Escribe el texto a traducir...", "Saisissez le texte à traduire...", "Inserisci il testo da tradurre...", "Digite o texto para traduzir..."),
        .dictatingPlaceholder: r("Listening…", "Говорите…", "Sprechen Sie…", "Hablando…", "Parlez…", "Parla…", "Falando…"),
        .outputPlaceholder: r("Translation will appear here...", "Перевод появится здесь...", "Übersetzung erscheint hier...",
                            "La traducción aparecerá aquí...", "La traduction apparaîtra ici...", "La traduzione apparirà qui...", "A tradução aparecerá aqui..."),
        .translatingPlaceholder: r("Translating...", "Перевод...", "Übersetzen...", "Traduciendo...", "Traduction...", "Traduzione...", "Traduzindo..."),
        .clear: r("Clear", "Очистить", "Leeren", "Borrar", "Effacer", "Cancella", "Limpar"),
        .voiceInputTip: r("Voice input", "Голосовой ввод", "Spracheingabe", "Entrada de voz", "Saisie vocale", "Input vocale", "Entrada de voz"),
        .forQuickCopy: r("for quick copy", "для быстрого копирования", "für schnelles Kopieren", "para copiar rápido",
                        "pour copier vite", "per copia rapida", "para cópia rápida"),
        .insertTranslation: r("Insert translation", "Вставить перевод", "Übersetzung einfügen", "Insertar traducción",
                             "Insérer la traduction", "Inserisci traduzione", "Inserir tradução"),
        .recordKeys: r("Press keys…", "Нажмите клавиши…", "Tasten drücken…", "Pulsa teclas…",
                      "Appuyez sur les touches…", "Premi i tasti…", "Pressione as teclas…"),
        .recordModifiers: r("Press modifiers…", "Нажмите модификаторы…", "Modifikatoren drücken…", "Pulsa modificadores…",
                           "Appuyez sur les modificateurs…", "Premi i modificatori…", "Pressione os modificadores…"),
        .errMicSpeech: r("Microphone permission is required.",
                        "Нужно разрешение «Микрофон».",
                        "Mikrofon-Berechtigung erforderlich.",
                        "Se requiere el permiso de Micrófono.",
                        "L’autorisation Microphone est requise.",
                        "È richiesto il permesso Microfono.",
                        "É necessária a permissão de Microfone."),
        .menuShow: r("Show BabelBar", "Показать BabelBar", "BabelBar anzeigen", "Mostrar BabelBar",
                    "Afficher BabelBar", "Mostra BabelBar", "Mostrar o BabelBar"),
        .menuSettings: r("Settings…", "Настройки…", "Einstellungen…", "Ajustes…", "Réglages…", "Impostazioni…", "Configurações…"),
        .menuQuit: r("Quit", "Выйти", "Beenden", "Salir", "Quitter", "Esci", "Sair"),

        .secSpeech: r("Speech", "Речь", "Sprache", "Voz", "Voix", "Voce", "Voz"),
        .recognition: r("Recognition", "Распознавание", "Erkennung", "Reconocimiento", "Reconnaissance", "Riconoscimento", "Reconhecimento"),
        .engineLocal: r("Local", "Локально", "Lokal", "Local", "Local", "Locale", "Local"),
        .engineRemote: r("Online", "Онлайн", "Online", "En línea", "En ligne", "Online", "Online"),
        .download: r("Download", "Скачать", "Laden", "Descargar", "Télécharger", "Scarica", "Baixar"),
        .downloading: r("Downloading…", "Загрузка…", "Wird geladen…", "Descargando…", "Téléchargement…", "Download…", "Baixando…"),
        .modelReady: r("Ready", "Готово", "Bereit", "Listo", "Prêt", "Pronto", "Pronto"),
        .downloaded: r("Downloaded", "Скачана", "Geladen", "Descargado", "Téléchargé", "Scaricato", "Baixado"),
        .initializing: r("Initializing…", "Идёт инициализация…", "Initialisierung…", "Inicializando…",
                        "Initialisation…", "Inizializzazione…", "Inicializando…"),
        .insertion: r("Insertion", "Вставка", "Einfügen", "Inserción", "Insertion", "Inserimento", "Inserção"),
        .insertPaste: r("Paste", "Буфер", "Einfügen", "Pegar", "Coller", "Incolla", "Colar"),
        .insertType: r("Type", "Печать", "Tippen", "Teclear", "Saisir", "Digita", "Digitar"),
        .remoteNote: r("Audio is sent to the server; internet required.",
                      "Аудио отправляется на сервер; нужен интернет.",
                      "Audio wird an den Server gesendet; Internet erforderlich.",
                      "El audio se envía al servidor; se requiere internet.",
                      "L’audio est envoyé au serveur ; internet requis.",
                      "L’audio viene inviato al server; richiede internet.",
                      "O áudio é enviado ao servidor; requer internet."),
        .tipSpeechEngine: r(
            "Local runs entirely on your Mac (free, offline, private) after a one-time model download. Online sends audio to a cloud Whisper API (needs an API key and internet).",
            "«Локально» работает целиком на Mac (бесплатно, офлайн, приватно) после разовой загрузки модели. «Онлайн» отправляет аудио в облачный Whisper-API (нужны ключ и интернет).",
            "Lokal läuft komplett auf deinem Mac (kostenlos, offline, privat) nach einmaligem Modell-Download. Online sendet Audio an eine Cloud-Whisper-API (braucht API-Schlüssel und Internet).",
            "Local funciona del todo en tu Mac (gratis, sin conexión, privado) tras descargar el modelo una vez. En línea envía el audio a una API Whisper en la nube (requiere clave e internet).",
            "Local fonctionne entièrement sur votre Mac (gratuit, hors ligne, privé) après un téléchargement unique du modèle. En ligne envoie l’audio à une API Whisper cloud (clé et internet requis).",
            "Locale gira interamente sul Mac (gratis, offline, privato) dopo un download una tantum del modello. Online invia l’audio a una API Whisper cloud (richiede chiave e internet).",
            "Local roda inteiramente no seu Mac (grátis, offline, privado) após baixar o modelo uma vez. Online envia o áudio a uma API Whisper na nuvem (requer chave e internet)."),
        .tipModelDownload: r(
            "base (~145 MB) — fast and light. Great for quick notes and clear speech, but can stumble on accents, jargon, or noisy audio.\n\nsmall (~480 MB) — the balanced pick. Noticeably more accurate, with better punctuation and terms; a bit slower and heavier. Best for most people.\n\nlarge-v3 (~626 MB) — the most accurate. Shines with accents, jargon, mixed languages, and noisy recordings. Heaviest and slowest; best on Apple Silicon.",
            "base (~145 МБ) — быстрая и лёгкая. Отлично для коротких заметок и чёткой речи, но может спотыкаться на акцентах, терминах и шуме.\n\nsmall (~480 МБ) — золотая середина. Заметно точнее, лучше пунктуация и термины; чуть медленнее и тяжелее. Подходит большинству.\n\nlarge-v3 (~626 МБ) — самая точная. Лучше всех с акцентами, жаргоном, смешанными языками и шумными записями. Самая тяжёлая и медленная; лучше на Apple Silicon.",
            "base (~145 MB) — schnell und leicht. Ideal für kurze Notizen und klare Sprache, kann aber bei Akzenten, Fachjargon oder Lärm patzen.\n\nsmall (~480 MB) — die ausgewogene Wahl. Deutlich genauer, bessere Zeichensetzung und Begriffe; etwas langsamer und größer. Für die meisten am besten.\n\nlarge-v3 (~626 MB) — am genauesten. Stark bei Akzenten, Jargon, gemischten Sprachen und lauten Aufnahmen. Am größten und langsamsten; am besten auf Apple Silicon.",
            "base (~145 MB) — rápido y ligero. Ideal para notas rápidas y voz clara, pero puede fallar con acentos, jerga o ruido.\n\nsmall (~480 MB) — la opción equilibrada. Bastante más preciso, mejor puntuación y términos; algo más lento y pesado. La mejor para la mayoría.\n\nlarge-v3 (~626 MB) — el más preciso. Destaca con acentos, jerga, idiomas mezclados y grabaciones ruidosas. El más pesado y lento; mejor en Apple Silicon.",
            "base (~145 Mo) — rapide et léger. Parfait pour des notes rapides et une voix claire, mais peut trébucher sur les accents, le jargon ou le bruit.\n\nsmall (~480 Mo) — le choix équilibré. Nettement plus précis, meilleure ponctuation et terminologie ; un peu plus lent et lourd. Le mieux pour la plupart.\n\nlarge-v3 (~626 Mo) — le plus précis. Excelle avec les accents, le jargon, les langues mêlées et les enregistrements bruyants. Le plus lourd et lent ; idéal sur Apple Silicon.",
            "base (~145 MB) — veloce e leggero. Ottimo per note rapide e voce chiara, ma può incespicare su accenti, gergo o rumore.\n\nsmall (~480 MB) — la scelta equilibrata. Decisamente più preciso, migliore punteggiatura e termini; un po' più lento e pesante. Il migliore per i più.\n\nlarge-v3 (~626 MB) — il più preciso. Brilla con accenti, gergo, lingue miste e registrazioni rumorose. Il più pesante e lento; meglio su Apple Silicon.",
            "base (~145 MB) — rápido e leve. Ótimo para notas rápidas e fala clara, mas pode tropeçar em sotaques, jargão ou ruído.\n\nsmall (~480 MB) — a opção equilibrada. Bem mais preciso, com melhor pontuação e termos; um pouco mais lento e pesado. O melhor para a maioria.\n\nlarge-v3 (~626 MB) — o mais preciso. Brilha com sotaques, jargão, idiomas misturados e gravações ruidosas. O mais pesado e lento; melhor em Apple Silicon."),
        .tipInsertMethod: r(
            "We've added two ways to insert the translated text into the app you're working in.\n\nPaste — the fastest and most reliable, even for long text: it copies the text, simulates ⌘V, then restores your previous clipboard. Recommended.\n\nType — enters one character at a time and never touches your clipboard. Use it only if your app blocks pasting; slower for long text.",
            "Мы реализовали два способа вставки переведённого текста в приложение, где ты работаешь.\n\nБуфер — самый быстрый и надёжный, даже для длинного текста: копирует текст, эмулирует ⌘V и возвращает прежнее содержимое буфера. Рекомендуется.\n\nПечать — набирает по одному символу и не трогает буфер обмена. Используйте, только если ваше приложение блокирует вставку; для длинного текста медленнее.",
            "Wir haben zwei Wege, den übersetzten Text in die App einzufügen, in der du arbeitest.\n\nEinfügen — am schnellsten und zuverlässigsten, auch bei langem Text: kopiert den Text, simuliert ⌘V und stellt deine vorherige Zwischenablage wieder her. Empfohlen.\n\nTippen — gibt Zeichen für Zeichen ein und rührt die Zwischenablage nicht an. Nur nutzen, wenn deine App das Einfügen blockiert; bei langem Text langsamer.",
            "Hemos añadido dos formas de insertar el texto traducido en la app en la que trabajas.\n\nPegar — lo más rápido y fiable, incluso con texto largo: copia el texto, simula ⌘V y restaura tu portapapeles anterior. Recomendado.\n\nTeclear — escribe carácter a carácter y no toca el portapapeles. Úsalo solo si tu app bloquea el pegado; más lento con texto largo.",
            "Nous proposons deux façons d'insérer le texte traduit dans l'app où vous travaillez.\n\nColler — le plus rapide et fiable, même pour un long texte : copie le texte, simule ⌘V, puis restaure votre presse-papiers précédent. Recommandé.\n\nSaisir — tape caractère par caractère et ne touche pas au presse-papiers. À utiliser uniquement si votre app bloque le collage ; plus lent pour un long texte.",
            "Abbiamo previsto due modi per inserire il testo tradotto nell'app in cui lavori.\n\nIncolla — il più veloce e affidabile, anche per testi lunghi: copia il testo, simula ⌘V e ripristina gli appunti precedenti. Consigliato.\n\nDigita — scrive un carattere alla volta e non tocca gli appunti. Usalo solo se la tua app blocca l'incolla; più lento per testi lunghi.",
            "Criamos duas formas de inserir o texto traduzido no app em que você trabalha.\n\nColar — o mais rápido e confiável, mesmo com texto longo: copia o texto, simula ⌘V e restaura sua área de transferência anterior. Recomendado.\n\nDigitar — digita um caractere por vez e não mexe na área de transferência. Use apenas se o seu app bloquear a colagem; mais lento com texto longo."),

        // API status
        .apiOffline: r("API Offline", "API офлайн", "API offline", "API sin conexión", "API hors ligne", "API offline", "API offline"),
        .apiNoTokens: r("No Tokens", "Нет токенов", "Keine Tokens", "Sin tokens", "Plus de jetons", "Nessun token", "Sem tokens"),
        .apiOnline: r("API Online", "API онлайн", "API online", "API en línea", "API en ligne", "API online", "API online"),

        // Tooltips
        .tipOpen: r(
            "Global hotkey that shows or hides the BabelBar window over any app (toggle). The window also hides with Escape.",
            "Глобальный хоткей, который показывает или прячет окно BabelBar поверх любого приложения (toggle). Окно также скрывается по Escape.",
            "Globales Tastenkürzel, das das BabelBar-Fenster über jeder App ein- oder ausblendet (Umschalten). Das Fenster wird auch mit Escape ausgeblendet.",
            "Atajo global que muestra u oculta la ventana de BabelBar sobre cualquier app (alternar). La ventana también se oculta con Escape.",
            "Raccourci global qui affiche ou masque la fenêtre BabelBar par-dessus toute app (bascule). La fenêtre se masque aussi avec Échap.",
            "Scorciatoia globale che mostra o nasconde la finestra di BabelBar sopra qualsiasi app (interruttore). La finestra si nasconde anche con Esc.",
            "Atalho global que mostra ou oculta a janela do BabelBar sobre qualquer app (alternar). A janela também oculta com Esc."),
        .tipTranslateAuto: r(
            "Double-press copies the selected text and translates it right away. Requires Input Monitoring permission.",
            "Двойное нажатие копирует выделенный текст и сразу переводит его. Нужно разрешение «Мониторинг ввода».",
            "Doppeltipp kopiert den markierten Text und übersetzt ihn sofort. Erfordert die Berechtigung „Eingabeüberwachung“.",
            "Pulsar dos veces copia el texto seleccionado y lo traduce al instante. Requiere el permiso «Monitorización de entrada».",
            "Un double appui copie le texte sélectionné et le traduit aussitôt. Nécessite l’autorisation « Surveillance des saisies ».",
            "La doppia pressione copia il testo selezionato e lo traduce subito. Richiede il permesso «Monitoraggio input».",
            "Pressionar duas vezes copia o texto selecionado e o traduz na hora. Requer a permissão «Monitoramento de entrada»."),
        .tipScreenshot: r(
            "Select a screen area — its text is recognized (OCR) and translated. Requires Screen Recording permission.",
            "Выдели область экрана — текст в ней распознаётся (OCR) и переводится. Нужно разрешение «Запись экрана».",
            "Wähle einen Bildschirmbereich — sein Text wird erkannt (OCR) und übersetzt. Erfordert die Berechtigung „Bildschirmaufnahme“.",
            "Selecciona un área de la pantalla — su texto se reconoce (OCR) y se traduce. Requiere el permiso «Grabación de pantalla».",
            "Sélectionnez une zone de l’écran — son texte est reconnu (OCR) et traduit. Nécessite l’autorisation « Enregistrement de l’écran ».",
            "Seleziona un’area dello schermo — il testo viene riconosciuto (OCR) e tradotto. Richiede il permesso «Registrazione schermo».",
            "Selecione uma área da tela — seu texto é reconhecido (OCR) e traduzido. Requer a permissão «Gravação de tela»."),
        .tipDictate: r(
            "Speak and your words are typed right where the cursor is, in any app. Hold the hotkey and talk, or tap to start and tap again to stop.\n\nNeeds Accessibility and Microphone. If you assign Fn, set Fn to “Do Nothing” in System Settings → Keyboard.",
            "Говори — и слова печатаются прямо там, где стоит курсор, в любом приложении. Удерживай хоткей и говори, или тапни, чтобы начать, и тапни снова, чтобы остановить.\n\nНужны «Универсальный доступ» и «Микрофон». Если назначишь Fn — в Системных настройках → Клавиатура поставь Fn на «Не выполнять действий».",
            "Sprich — und deine Worte werden direkt dort getippt, wo der Cursor steht, in jeder App. Halte das Kürzel gedrückt und sprich, oder tippe zum Starten und nochmals zum Stoppen.\n\nBenötigt Bedienungshilfen und Mikrofon. Wenn du Fn zuweist, stelle Fn in Systemeinstellungen → Tastatur auf „Nichts tun“.",
            "Habla y tus palabras se escriben justo donde está el cursor, en cualquier app. Mantén pulsado el atajo y habla, o toca para empezar y toca de nuevo para parar.\n\nNecesita Accesibilidad y Micrófono. Si asignas Fn, pon Fn en «No hacer nada» en Ajustes del Sistema → Teclado.",
            "Parlez et vos mots sont saisis là où se trouve le curseur, dans toute app. Maintenez le raccourci et parlez, ou appuyez pour démarrer et de nouveau pour arrêter.\n\nNécessite Accessibilité et Microphone. Si vous assignez Fn, réglez Fn sur « Ne rien faire » dans Réglages Système → Clavier.",
            "Parla e le tue parole vengono digitate proprio dove si trova il cursore, in qualsiasi app. Tieni premuta la scorciatoia e parla, o tocca per iniziare e tocca di nuovo per fermare.\n\nRichiede Accessibilità e Microfono. Se assegni Fn, imposta Fn su «Non fare nulla» in Impostazioni di Sistema → Tastiera.",
            "Fale e suas palavras são digitadas bem onde está o cursor, em qualquer app. Segure o atalho e fale, ou toque para começar e toque de novo para parar.\n\nRequer Acessibilidade e Microfone. Se atribuir Fn, defina Fn como «Não fazer nada» em Ajustes do Sistema → Teclado."),
        .tipAIInstructions: r(
            "Extra guidance for the translation model — e.g. fix typos, keep certain terms untranslated, or follow a style. Appended to the system prompt on every request.",
            "Дополнительные указания для модели перевода — например, исправлять опечатки, не переводить определённые термины или придерживаться стиля. Добавляются к системному промпту при каждом запросе.",
            "Zusätzliche Hinweise für das Übersetzungsmodell — z. B. Tippfehler korrigieren, bestimmte Begriffe unübersetzt lassen oder einem Stil folgen. Werden bei jeder Anfrage an den System-Prompt angehängt.",
            "Indicaciones adicionales para el modelo de traducción — p. ej. corregir erratas, no traducir ciertos términos o seguir un estilo. Se añaden al prompt del sistema en cada solicitud.",
            "Consignes supplémentaires pour le modèle de traduction — p. ex. corriger les fautes, ne pas traduire certains termes ou suivre un style. Ajoutées au prompt système à chaque requête.",
            "Indicazioni aggiuntive per il modello di traduzione — es. correggere refusi, non tradurre certi termini o seguire uno stile. Aggiunte al prompt di sistema a ogni richiesta.",
            "Orientações extras para o modelo de tradução — ex.: corrigir erros de digitação, manter certos termos sem tradução ou seguir um estilo. Anexadas ao prompt do sistema em cada solicitação."),
        .tipShowRecordingDot: r(
            "Show or hide the red indicator next to the voice-input animation.",
            "Показывать или скрывать рядом с анимацией голосового набора красный индикатор.",
            "Den roten Indikator neben der Spracheingabe-Animation ein- oder ausblenden.",
            "Mostrar u ocultar el indicador rojo junto a la animación de entrada de voz.",
            "Afficher ou masquer l’indicateur rouge à côté de l’animation de saisie vocale.",
            "Mostra o nascondi l’indicatore rosso accanto all’animazione di input vocale.",
            "Mostrar ou ocultar o indicador vermelho ao lado da animação de entrada de voz."),
        .tipDuckAudio: r(
            "Lowers the system output volume while you dictate, so music or other audio playing through the speakers doesn't bleed into the microphone. The volume is restored as soon as you stop.",
            "Приглушает общую громкость системы на время диктовки, чтобы музыка или другой звук из колонок не попадал в микрофон. Громкость возвращается, как только ты остановишь запись.",
            "Senkt die System-Lautstärke während des Diktierens, damit Musik oder anderer Ton aus den Lautsprechern nicht ins Mikrofon gelangt. Die Lautstärke wird beim Stoppen wiederhergestellt.",
            "Baja el volumen del sistema mientras dictas, para que la música u otro audio de los altavoces no se cuele en el micrófono. Se restaura al detener.",
            "Réduit le volume du système pendant la dictée, pour que la musique ou un autre son des haut-parleurs n’entre pas dans le micro. Le volume est rétabli dès l’arrêt.",
            "Abbassa il volume di sistema durante la dettatura, così la musica o altro audio dagli altoparlanti non entra nel microfono. Il volume viene ripristinato allo stop.",
            "Abaixa o volume do sistema enquanto você dita, para que música ou outro áudio dos alto-falantes não entre no microfone. O volume é restaurado ao parar."),
    ]
}
