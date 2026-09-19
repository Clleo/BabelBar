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
    case secGeneral, secAbout
    // App settings
    case launchAtLogin, showMenuBarIcon, openBabelBar, translateAuto, translateScreenshot
    // Updates
    case autoCheckUpdates, checkForUpdatesNow, checkingUpdates, lastChecked, neverChecked
    case updateUpToDate, updateAvailableFmt, updateFailed, updateDownload
    case updateInstallNow, updateInstalling, updateBannerFmt, updateBannerAction
    // GitHub star card
    case githubStar, recentlyStarred, starsWord
    case languagePreferences, interfaceLanguage, source, target, autoDetect
    // Voice
    case dictateToCursor, translateAtCursor, triggerSound, showRecordingDot, duckAudio
    case voiceCommands, dictationCleanup, dictationInstructions
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
    case errMicSpeech, errDictation, errSilence, errCapture
    case errTranslationOriginal, menuShow, menuSettings, menuQuit
    // Speech engine section
    case secSpeech, recognition, engineLocal, engineRemote
    case download, downloading, modelReady, downloaded, initializing, insertion, insertPaste, insertType
    case remoteNote
    case tipSpeechEngine, tipModelDownload, tipInsertMethod
    // API status
    case apiOffline, apiNoTokens, apiOnline
    // Tooltips
    case tipOpen, tipTranslateAuto, tipScreenshot, tipDictate, tipTranslateAtCursor, tipAIInstructions
    case tipShowRecordingDot, tipDuckAudio, tipVoiceCommands, tipDictationCleanup
    // Onboarding
    case obWelcomeTitle, obWelcomeSubtitle, obBack, obContinue, obSkip, obGetStarted, obGrantAccess
    case obPermAccessibilityDesc, obPermInputDesc, obPermScreenDesc, obPermMicDesc
    case obApiKeyTitle, obApiKeySubtitle, obApiKeySkipNote, obGetApiKeyFmt
    case obFinishTitle, obFinishSubtitle
    // Live dictation (v3.0)
    case secDictionary, liveDictation, liveOnDevice, liveLanguageLabel
    case devDictionary, personalDictionary, learnedSuggestions, learnCorrections, freqLearning
    case spokenForm, writtenForm, addRule, removeRule, resetStatistics
    case timesSeenFmt, dismiss, noSuggestions, suggestionsHint
    case tipLiveDictation, tipLiveOnDevice, tipDevDictionary, tipPersonalDict, tipLearn, tipFreq
    case errSpeechDenied, errSpeechUnavailable, errSpeechOnDevice, errLiveField
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
        .errLiveField: ["Place the cursor in an editable text field and allow Accessibility access.", "Поставьте курсор в редактируемое поле и разрешите Универсальный доступ."],
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
        .secGeneral: r("General", "Общее", "Allgemein", "General", "Général", "Generali", "Geral"),
        .secAbout: r("About", "О приложении", "Über", "Acerca de", "À propos", "Informazioni", "Sobre"),

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
        .updateBannerFmt: r("BabelBar %@ is available", "Доступна новая версия BabelBar %@",
                           "BabelBar %@ ist verfügbar", "BabelBar %@ ya está disponible",
                           "BabelBar %@ est disponible", "BabelBar %@ è disponibile",
                           "BabelBar %@ está disponível"),
        .updateBannerAction: r("View", "Подробнее", "Ansehen", "Ver", "Voir", "Vedi", "Ver"),
        .updateInstallNow: r("Install Update", "Установить обновление", "Update installieren", "Instalar actualización",
                            "Installer la mise à jour", "Installa aggiornamento", "Instalar atualização"),
        .updateInstalling: r("Installing…", "Установка…", "Installation läuft…", "Instalando…",
                            "Installation…", "Installazione…", "Instalando…"),

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
        .translateAtCursor: r("Dictate & translate to cursor", "Диктовать и переводить под курсор",
                             "Diktieren & übersetzen an Cursor", "Dictar y traducir en el cursor",
                             "Dicter et traduire au curseur", "Detta e traduci al cursore",
                             "Ditar e traduzir no cursor"),
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
        .voiceCommands: r("Spoken punctuation", "Знаки препинания голосом",
                          "Satzzeichen per Sprache", "Puntuación por voz",
                          "Ponctuation dictée", "Punteggiatura vocale", "Pontuação por voz"),
        .dictationCleanup: r("AI cleanup of dictation", "Обработка диктовки ИИ",
                             "KI-Nachbearbeitung des Diktats", "Limpieza del dictado con IA",
                             "Nettoyage IA de la dictée", "Pulizia della dettatura con IA",
                             "Limpeza do ditado com IA"),
        .dictationInstructions: r("Dictation rules", "Правила диктовки", "Diktier-Regeln",
                                  "Reglas de dictado", "Règles de dictée", "Regole di dettatura",
                                  "Regras de ditado"),

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
        .errDictation: r("Dictation failed",
                        "Ошибка диктовки",
                        "Diktat fehlgeschlagen",
                        "Error de dictado",
                        "Échec de la dictée",
                        "Dettatura non riuscita",
                        "Falha no ditado"),
        .errSilence: r("Nothing was heard — check the microphone",
                        "Ничего не слышно — проверьте микрофон",
                        "Nichts gehört — Mikrofon prüfen",
                        "No se oyó nada: revisa el micrófono",
                        "Rien n’a été entendu — vérifiez le microphone",
                        "Non si sente nulla — controlla il microfono",
                        "Nada foi ouvido — verifique o microfone"),
        .errCapture: r("Microphone is sending broken audio",
                        "Микрофон отдаёт битый звук",
                        "Mikrofon liefert fehlerhaften Ton",
                        "El micrófono envía audio dañado",
                        "Le microphone envoie un son corrompu",
                        "Il microfono invia audio corrotto",
                        "O microfone está enviando áudio corrompido"),
        .errTranslationOriginal: r("Translation failed — inserted original",
                        "Перевод не удался — вставлен оригинал",
                        "Übersetzung fehlgeschlagen — Original eingefügt",
                        "Error de traducción: se insertó el original",
                        "Échec de la traduction — original inséré",
                        "Traduzione non riuscita — inserito l’originale",
                        "Falha na tradução — original inserido"),
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
        .tipTranslateAtCursor: r(
            "Speak in any app — your words are translated to the configured language in the background and typed right where the cursor is. Hold the hotkey and talk, or tap to start and tap again to stop.\n\nDirection follows your Source/Target settings (auto-detected). Needs Accessibility and Microphone. If you assign Fn, set Fn to “Do Nothing” in System Settings → Keyboard.",
            "Говори в любом приложении — слова переводятся на заданный язык в фоне и печатаются прямо там, где стоит курсор. Удерживай хоткей и говори, или тапни, чтобы начать, и тапни снова, чтобы остановить.\n\nНаправление берётся из настроек «Источник/Цель» (определяется автоматически). Нужны «Универсальный доступ» и «Микрофон». Если назначишь Fn — в Системных настройках → Клавиатура поставь Fn на «Не выполнять действий».",
            "Sprich in jeder App — deine Worte werden im Hintergrund in die eingestellte Sprache übersetzt und direkt am Cursor getippt. Halte das Kürzel gedrückt und sprich, oder tippe zum Starten und nochmals zum Stoppen.\n\nDie Richtung folgt deinen Quelle/Ziel-Einstellungen (automatisch erkannt). Benötigt Bedienungshilfen und Mikrofon. Wenn du Fn zuweist, stelle Fn in Systemeinstellungen → Tastatur auf „Nichts tun“.",
            "Habla en cualquier app: tus palabras se traducen al idioma configurado en segundo plano y se escriben justo donde está el cursor. Mantén pulsado el atajo y habla, o toca para empezar y toca de nuevo para parar.\n\nLa dirección sigue tus ajustes de Origen/Destino (detección automática). Necesita Accesibilidad y Micrófono. Si asignas Fn, pon Fn en «No hacer nada» en Ajustes del Sistema → Teclado.",
            "Parlez dans n’importe quelle app : vos mots sont traduits dans la langue configurée en arrière-plan et saisis là où se trouve le curseur. Maintenez le raccourci et parlez, ou appuyez pour démarrer et de nouveau pour arrêter.\n\nLe sens suit vos réglages Source/Cible (détection automatique). Nécessite Accessibilité et Microphone. Si vous assignez Fn, réglez Fn sur « Ne rien faire » dans Réglages Système → Clavier.",
            "Parla in qualsiasi app: le tue parole vengono tradotte nella lingua configurata in background e digitate proprio dove si trova il cursore. Tieni premuta la scorciatoia e parla, o tocca per iniziare e tocca di nuovo per fermare.\n\nLa direzione segue le impostazioni Origine/Destinazione (rilevamento automatico). Richiede Accessibilità e Microfono. Se assegni Fn, imposta Fn su «Non fare nulla» in Impostazioni di Sistema → Tastiera.",
            "Fale em qualquer app: suas palavras são traduzidas para o idioma configurado em segundo plano e digitadas bem onde está o cursor. Segure o atalho e fale, ou toque para começar e toque de novo para parar.\n\nA direção segue seus ajustes de Origem/Destino (detecção automática). Requer Acessibilidade e Microfone. Se atribuir Fn, defina Fn como «Não fazer nada» em Ajustes do Sistema → Teclado."),
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
        .tipVoiceCommands: r(
            "Say «comma», «period», «colon», «dash», «new line» and the mark itself is inserted instead of the word. Works offline, in every dictation mode, with no delay. Only the plain dictionary form counts as a command, so a sentence that mentions punctuation stays as text.",
            "Скажи «запятая», «точка», «двоеточие», «тире», «с новой строки» — вместо слова подставится сам знак. Работает офлайн, во всех режимах диктовки и без задержки. Командой считается только слово в именительном падеже, поэтому фраза, где знак просто упоминается («поставь запятую»), останется текстом.",
            "Sag «Komma», «Punkt», «Doppelpunkt», «Gedankenstrich», «neue Zeile» — statt des Wortes wird das Zeichen eingefügt. Funktioniert offline, in jedem Diktiermodus und ohne Verzögerung. Nur die Grundform zählt als Befehl, ein Satz, der ein Satzzeichen bloß erwähnt, bleibt Text.",
            "Di «coma», «punto», «dos puntos», «guion», «nueva línea» y se inserta el signo en lugar de la palabra. Funciona sin conexión, en todos los modos de dictado y sin retardo. Solo la forma básica cuenta como comando, así que una frase que menciona el signo se queda como texto.",
            "Dis «virgule», «point», «deux-points», «tiret», «nouvelle ligne» : le signe est inséré à la place du mot. Fonctionne hors ligne, dans tous les modes de dictée et sans délai. Seule la forme de base compte comme commande, une phrase qui mentionne la ponctuation reste du texte.",
            "Di' «virgola», «punto», «due punti», «trattino», «a capo»: al posto della parola viene inserito il segno. Funziona offline, in ogni modalità di dettatura e senza ritardo. Solo la forma base vale come comando, così una frase che nomina la punteggiatura resta testo.",
            "Diga «vírgula», «ponto», «dois-pontos», «travessão», «nova linha» e o sinal é inserido no lugar da palavra. Funciona offline, em todos os modos de ditado e sem atraso. Só a forma básica conta como comando, então uma frase que menciona a pontuação continua sendo texto."),
        .tipDictationCleanup: r(
            "Runs every transcript through your translation API to fix punctuation, capitalization and recognition slips by your own rules. Costs tokens and adds about a second to each dictation; if it fails, the raw transcript is inserted unchanged.",
            "Прогоняет каждую расшифровку через твой API перевода: чинит пунктуацию, заглавные буквы и оговорки по твоим правилам. Тратит токены и добавляет около секунды к каждой диктовке; если запрос не удался, вставится исходный текст.",
            "Schickt jedes Transkript durch deine Übersetzungs-API, um Satzzeichen, Großschreibung und Erkennungsfehler nach deinen Regeln zu korrigieren. Kostet Tokens und dauert rund eine Sekunde pro Diktat; schlägt es fehl, wird das Original eingefügt.",
            "Pasa cada transcripción por tu API de traducción para corregir puntuación, mayúsculas y errores de reconocimiento según tus reglas. Consume tokens y añade cerca de un segundo por dictado; si falla, se inserta el texto original.",
            "Fait passer chaque transcription par ton API de traduction pour corriger la ponctuation, les majuscules et les erreurs de reconnaissance selon tes règles. Consomme des tokens et ajoute environ une seconde par dictée ; en cas d'échec, le texte brut est inséré.",
            "Passa ogni trascrizione attraverso la tua API di traduzione per correggere punteggiatura, maiuscole ed errori di riconoscimento secondo le tue regole. Consuma token e aggiunge circa un secondo per dettatura; se fallisce, viene inserito il testo originale.",
            "Passa cada transcrição pela sua API de tradução para corrigir pontuação, maiúsculas e falhas de reconhecimento conforme suas regras. Consome tokens e adiciona cerca de um segundo por ditado; se falhar, o texto original é inserido."),

        // Onboarding
        .obWelcomeTitle: r("Welcome to BabelBar", "Добро пожаловать в BabelBar", "Willkommen bei BabelBar",
                          "Bienvenido a BabelBar", "Bienvenue sur BabelBar", "Benvenuto in BabelBar",
                          "Bem-vindo ao BabelBar"),
        .obWelcomeSubtitle: r(
            "Instant translation and voice dictation, right where you're typing. Let's get you set up in under a minute.",
            "Мгновенный перевод и голосовой ввод прямо там, где ты печатаешь. Настроим всё меньше чем за минуту.",
            "Sofortübersetzung und Spracheingabe, genau dort, wo du tippst. Die Einrichtung dauert weniger als eine Minute.",
            "Traducción instantánea y dictado por voz, justo donde escribes. Vamos a configurarlo en menos de un minuto.",
            "Traduction instantanée et dictée vocale, là où vous tapez. Configurons tout ça en moins d’une minute.",
            "Traduzione istantanea e dettatura vocale, proprio dove stai scrivendo. Configuriamo tutto in meno di un minuto.",
            "Tradução instantânea e ditado por voz, bem onde você está digitando. Vamos configurar tudo em menos de um minuto."),
        .obBack: r("Back", "Назад", "Zurück", "Atrás", "Retour", "Indietro", "Voltar"),
        .obContinue: r("Continue", "Продолжить", "Weiter", "Continuar", "Continuer", "Continua", "Continuar"),
        .obSkip: r("Skip", "Пропустить", "Überspringen", "Omitir", "Ignorer", "Salta", "Pular"),
        .obGetStarted: r("Get Started", "Начать работу", "Loslegen", "Empezar", "Commencer", "Inizia", "Começar"),
        .obGrantAccess: r("Grant Access", "Разрешить доступ", "Zugriff erlauben", "Conceder acceso",
                         "Autoriser l’accès", "Concedi accesso", "Conceder acesso"),
        .obPermAccessibilityDesc: r(
            "Lets BabelBar paste translations and typed dictation into whatever app you're working in.",
            "Позволяет BabelBar вставлять переводы и надиктованный текст в любое приложение, где ты работаешь.",
            "Ermöglicht BabelBar, Übersetzungen und diktierten Text in die App einzufügen, in der du gerade arbeitest.",
            "Permite que BabelBar pegue traducciones y texto dictado en la app en la que estés trabajando.",
            "Permet à BabelBar de coller les traductions et le texte dicté dans l’app où vous travaillez.",
            "Consente a BabelBar di incollare traduzioni e testo dettato nell’app in cui stai lavorando.",
            "Permite que o BabelBar cole traduções e texto ditado no app em que você está trabalhando."),
        .obPermInputDesc: r(
            "Lets BabelBar detect its global shortcuts — like double-tapping ⌘C to translate a selection — from any app.",
            "Позволяет BabelBar отслеживать глобальные хоткеи — например, двойное ⌘C для перевода выделения — в любом приложении.",
            "Ermöglicht BabelBar, seine globalen Tastenkürzel zu erkennen — z. B. doppeltes ⌘C zum Übersetzen einer Auswahl — in jeder App.",
            "Permite que BabelBar detecte sus atajos globales — como pulsar ⌘C dos veces para traducir una selección — en cualquier app.",
            "Permet à BabelBar de détecter ses raccourcis globaux — comme un double ⌘C pour traduire une sélection — dans toute app.",
            "Consente a BabelBar di rilevare le sue scorciatoie globali — come doppio ⌘C per tradurre una selezione — in qualsiasi app.",
            "Permite que o BabelBar detecte seus atalhos globais — como pressionar ⌘C duas vezes para traduzir uma seleção — em qualquer app."),
        .obPermScreenDesc: r(
            "Lets BabelBar capture a screen region so it can recognize and translate the text in it.",
            "Позволяет BabelBar захватывать область экрана, чтобы распознать и перевести текст на ней.",
            "Ermöglicht BabelBar, einen Bildschirmbereich zu erfassen, um den Text darin zu erkennen und zu übersetzen.",
            "Permite que BabelBar capture una zona de la pantalla para reconocer y traducir el texto que contiene.",
            "Permet à BabelBar de capturer une zone de l’écran pour reconnaître et traduire le texte qu’elle contient.",
            "Consente a BabelBar di catturare un’area dello schermo per riconoscere e tradurre il testo al suo interno.",
            "Permite que o BabelBar capture uma área da tela para reconhecer e traduzir o texto nela."),
        .obPermMicDesc: r(
            "Lets BabelBar record your voice for dictation and voice-to-translation.",
            "Позволяет BabelBar записывать твой голос для диктовки и голосового перевода.",
            "Ermöglicht BabelBar, deine Stimme für Diktat und Sprachübersetzung aufzuzeichnen.",
            "Permite que BabelBar grabe tu voz para el dictado y la traducción por voz.",
            "Permet à BabelBar d’enregistrer votre voix pour la dictée et la traduction vocale.",
            "Consente a BabelBar di registrare la tua voce per la dettatura e la traduzione vocale.",
            "Permite que o BabelBar grave sua voz para ditado e tradução por voz."),
        .obApiKeyTitle: r("Connect a Translation Provider", "Подключи провайдера перевода",
                         "Übersetzungsanbieter verbinden", "Conecta un proveedor de traducción",
                         "Connectez un fournisseur de traduction", "Collega un provider di traduzione",
                         "Conecte um provedor de tradução"),
        .obApiKeySubtitle: r(
            "BabelBar uses your own API key with OpenAI, DeepSeek, or another compatible provider — your text goes straight to them, never through our servers.",
            "BabelBar использует твой собственный API-ключ — OpenAI, DeepSeek или другой совместимый провайдер. Текст уходит напрямую к нему, минуя наши серверы.",
            "BabelBar nutzt deinen eigenen API-Schlüssel — OpenAI, DeepSeek oder einen anderen kompatiblen Anbieter. Dein Text geht direkt dorthin, nie über unsere Server.",
            "BabelBar usa tu propia clave API — OpenAI, DeepSeek u otro proveedor compatible. Tu texto va directo a ellos, nunca por nuestros servidores.",
            "BabelBar utilise votre propre clé API — OpenAI, DeepSeek ou un autre fournisseur compatible. Votre texte va directement chez eux, jamais via nos serveurs.",
            "BabelBar usa la tua chiave API — OpenAI, DeepSeek o un altro provider compatibile. Il tuo testo va direttamente a loro, mai attraverso i nostri server.",
            "O BabelBar usa sua própria chave de API — OpenAI, DeepSeek ou outro provedor compatível. Seu texto vai direto para eles, nunca pelos nossos servidores."),
        .obApiKeySkipNote: r(
            "No key yet? Skip this — you can add one anytime in Settings → API.",
            "Нет ключа? Пропусти этот шаг — добавить его можно в любой момент в Настройки → API.",
            "Noch keinen Schlüssel? Überspringe diesen Schritt — du kannst jederzeit einen in Einstellungen → API hinzufügen.",
            "¿Aún sin clave? Omite este paso — puedes añadir una cuando quieras en Ajustes → API.",
            "Pas encore de clé ? Ignorez cette étape — vous pourrez en ajouter une à tout moment dans Réglages → API.",
            "Non hai ancora una chiave? Salta questo passaggio — puoi aggiungerla in qualsiasi momento in Impostazioni → API.",
            "Ainda sem chave? Pule esta etapa — você pode adicionar uma a qualquer momento em Configurações → API."),
        .obGetApiKeyFmt: r("Get a %@ API key", "Получить API-ключ %@", "%@ API-Schlüssel holen", "Obtener una clave API de %@",
                          "Obtenir une clé API %@", "Ottieni una chiave API %@", "Obter uma chave de API da %@"),
        .obFinishTitle: r("You're all set!", "Всё готово!", "Fertig eingerichtet!", "¡Todo listo!",
                         "Tout est prêt !", "Tutto pronto!", "Tudo pronto!"),
        .obFinishSubtitle: r(
            "Here are the shortcuts you'll use most. You can change any of them later in Settings.",
            "Вот хоткеи, которые ты будешь использовать чаще всего. Их можно изменить позже в Настройках.",
            "Hier sind die Kürzel, die du am häufigsten brauchst. Du kannst sie später in den Einstellungen ändern.",
            "Estos son los atajos que más usarás. Puedes cambiarlos luego en Ajustes.",
            "Voici les raccourcis que vous utiliserez le plus. Vous pourrez les modifier plus tard dans les Réglages.",
            "Ecco le scorciatoie che userai più spesso. Potrai cambiarle in seguito nelle Impostazioni.",
            "Aqui estão os atalhos que você mais usará. Você pode alterá-los depois em Configurações."),

        // Live dictation (v3.0)
        .secDictionary: r("Dictionary", "Словарь", "Wörterbuch", "Diccionario", "Dictionnaire", "Dizionario", "Dicionário"),
        .liveDictation: r("Live Dictation", "Живая диктовка", "Live-Diktat", "Dictado en vivo",
                          "Dictée en direct", "Dettatura in tempo reale", "Ditado ao vivo"),
        .liveOnDevice: r("On-device recognition only", "Только локальное распознавание",
                         "Nur On-Device-Erkennung", "Solo reconocimiento local",
                         "Reconnaissance sur l’appareil uniquement", "Solo riconoscimento locale",
                         "Somente reconhecimento no dispositivo"),
        .liveLanguageLabel: r("Recognition language", "Язык распознавания", "Erkennungssprache",
                              "Idioma de reconocimiento", "Langue de reconnaissance",
                              "Lingua di riconoscimento", "Idioma de reconhecimento"),
        .devDictionary: r("Developer Dictionary", "Словарь разработчика", "Entwickler-Wörterbuch",
                          "Diccionario de desarrollador", "Dictionnaire développeur",
                          "Dizionario per sviluppatori", "Dicionário do desenvolvedor"),
        .personalDictionary: r("Personal Dictionary", "Персональный словарь", "Persönliches Wörterbuch",
                               "Diccionario personal", "Dictionnaire personnel",
                               "Dizionario personale", "Dicionário pessoal"),
        .learnedSuggestions: r("Learned suggestions", "Выученные варианты", "Gelernte Vorschläge",
                               "Sugerencias aprendidas", "Suggestions apprises",
                               "Suggerimenti appresi", "Sugestões aprendidas"),
        .learnCorrections: r("Learn from my corrections", "Учиться по моим правкам",
                             "Aus meinen Korrekturen lernen", "Aprender de mis correcciones",
                             "Apprendre de mes corrections", "Impara dalle mie correzioni",
                             "Aprender com minhas correções"),
        .freqLearning: r("Frequency learning", "Частотное обучение", "Häufigkeitslernen",
                         "Aprendizaje por frecuencia", "Apprentissage par fréquence",
                         "Apprendimento per frequenza", "Aprendizado por frequência"),
        .spokenForm: r("You say", "Произносишь", "Du sagst", "Dices", "Tu dis", "Dici", "Você diz"),
        .writtenForm: r("Types as", "Печатается", "Wird zu", "Se escribe", "S’écrit", "Si scrive", "Digita como"),
        .addRule: r("Add", "Добавить", "Hinzufügen", "Añadir", "Ajouter", "Aggiungi", "Adicionar"),
        .removeRule: r("Remove", "Убрать", "Entfernen", "Quitar", "Retirer", "Rimuovi", "Remover"),
        .resetStatistics: r("Reset statistics", "Сбросить статистику", "Statistik zurücksetzen",
                            "Restablecer estadísticas", "Réinitialiser les statistiques",
                            "Azzera statistiche", "Redefinir estatísticas"),
        .timesSeenFmt: r("seen %d×", "замечено %d×", "%d× gesehen", "visto %d×",
                         "vu %d×", "visto %d×", "visto %d×"),
        .dismiss: r("Dismiss", "Скрыть", "Verwerfen", "Descartar", "Ignorer", "Scarta", "Descartar"),
        .noSuggestions: r("No suggestions yet — keep dictating and correcting.",
                          "Подсказок пока нет — диктуй и исправляй.",
                          "Noch keine Vorschläge — diktiere weiter und korrigiere.",
                          "Aún no hay sugerencias — sigue dictando y corrigiendo.",
                          "Pas encore de suggestions — continuez à dicter et corriger.",
                          "Ancora nessun suggerimento — continua a dettare e correggere.",
                          "Ainda sem sugestões — continue ditando e corrigindo."),
        .suggestionsHint: r("Repeated identical corrections appear here.",
                            "Повторяющиеся одинаковые исправления появляются здесь.",
                            "Wiederholte identische Korrekturen erscheinen hier.",
                            "Las correcciones idénticas repetidas aparecen aquí.",
                            "Les corrections identiques répétées apparaissent ici.",
                            "Le correzioni identiche ripetute appaiono qui.",
                            "Correções idênticas repetidas aparecem aqui."),
        .tipLiveDictation: r(
            "Tap Fn to start dictation; tap again to stop. You can also hold Fn while speaking. Text appears in the active editable field. Typing, clicking or changing fields ends the session; press Fn again to continue at the new cursor position. Requires Microphone, Speech Recognition and Accessibility. Set Fn to “Do Nothing” in System Settings → Keyboard.",
            "Нажмите Fn, чтобы начать диктовку, и ещё раз — чтобы остановить. Можно также удерживать Fn во время речи. Текст появляется в активном редактируемом поле. Ручной ввод, щелчок мышью или смена поля завершают сессию; нажмите Fn снова, чтобы продолжить с новой позиции курсора. Нужны Микрофон, Распознавание речи и Универсальный доступ. В Системных настройках → Клавиатура установите для Fn «Не выполнять действий».",
            "Drücke Fn zum Starten und erneut zum Stoppen. Du kannst Fn auch beim Sprechen halten. Texteingabe, Klicks oder Feldwechsel beenden die Sitzung. Drücke Fn erneut, um am neuen Cursor fortzufahren. Mikrofon, Spracherkennung und Bedienungshilfen müssen erlaubt sein.",
            "Pulsa Fn para iniciar y otra vez para detener el dictado. También puedes mantener Fn pulsado. Escribir, hacer clic o cambiar de campo termina la sesión. Pulsa Fn para continuar desde el nuevo cursor. Requiere Micrófono, Reconocimiento de voz y Accesibilidad.",
            "Appuyez sur Fn pour démarrer, puis à nouveau pour arrêter. Vous pouvez aussi maintenir Fn. Une saisie manuelle, un clic ou un changement de champ termine la session. Appuyez sur Fn pour reprendre au nouveau curseur. Microphone, reconnaissance vocale et accessibilité requis.",
            "Premi Fn per iniziare e di nuovo per fermare la dettatura. Puoi anche tenere premuto Fn. Scrivere, fare clic o cambiare campo termina la sessione. Premi Fn per continuare dal nuovo cursore. Sono richiesti microfono, riconoscimento vocale e accessibilità.",
            "Pressione Fn para iniciar e novamente para parar. Também pode segurar Fn enquanto fala. Digitar, clicar ou mudar de campo encerra a sessão. Pressione Fn para continuar no novo cursor. Requer Microfone, Reconhecimento de Fala e Acessibilidade."),
        .tipLiveOnDevice: r(
            "Live dictation prefers on-device recognition: offline, private, and with no time limit. When the language has no on-device model, recognition goes through Apple's servers — unless you enable this switch, which then refuses to start instead.",
            "Живая диктовка предпочитает локальное распознавание: офлайн, приватно и без ограничения по времени. Если у языка нет локальной модели, распознавание пойдёт через серверы Apple — если не включить этот переключатель: тогда приложение просто не начнёт сессию.",
            "Live-Diktat bevorzugt On-Device-Erkennung: offline, privat, ohne Zeitlimit. Hat die Sprache kein lokales Modell, läuft die Erkennung über Apples Server — außer du aktivierst diesen Schalter: dann startet die Sitzung gar nicht.",
            "El dictado en vivo prefiere el reconocimiento local: sin conexión, privado y sin límite de tiempo. Si el idioma no tiene modelo local, el reconocimiento pasa por los servidores de Apple — salvo que actives este interruptor: entonces la sesión ni siquiera comienza.",
            "La dictée en direct préfère la reconnaissance sur l’appareil : hors ligne, privé, sans limite de temps. Si la langue n’a pas de modèle local, la reconnaissance passe par les serveurs d’Apple — sauf si vous activez ce commutateur : la séance ne démarre alors pas.",
            "La dettatura in tempo reale preferisce il riconoscimento locale: offline, privato e senza limiti di tempo. Se la lingua non ha un modello locale, il riconoscimento passa dai server di Apple — a meno che tu attivi questo interruttore: in tal caso la sessione non parte proprio.",
            "O ditado ao vivo prefere o reconhecimento no dispositivo: offline, privado e sem limite de tempo. Se o idioma não tem modelo local, o reconhecimento vai pelos servidores da Apple — exceto se você ativar esta opção: nesse caso, a sessão nem começa."),
        .tipDevDictionary: r(
            "A built-in vocabulary of modern dev terminology — frameworks, tools, AI, casing conventions. It biases recognition toward correct terms and phonetically rewrites what you say in Russian into the proper spelling (\"тайп скрипт\" → TypeScript). It grows with app updates.",
            "Встроенный словарь современной дев-терминологии — фреймворки, инструменты, ИИ, соглашения о регистре. Он смещает распознавание к правильным терминам и фонетически переписывает произнесённое по-русски в корректное написание («тайп скрипт» → TypeScript). Словарь пополняется с обновлениями приложения.",
            "Ein eingebauter Wortschatz moderner Dev-Terminologie — Frameworks, Tools, KI, Namenskonventionen. Er lenkt die Erkennung auf korrekte Begriffe und schreibt phonetisch Ausgesprochenes Russisch in die richtige Schreibweise um („тайп скрипт“ → TypeScript). Wächst mit App-Updates.",
            "Un vocabulario integrado de terminología dev moderna — frameworks, herramientas, IA, convenciones de nombres. Sesga el reconocimiento hacia términos correctos y reescribe fonéticamente lo dicho en ruso con la grafía adecuada («тайп скрипт» → TypeScript). Crece con las actualizaciones.",
            "Un vocabulaire intégré de terminologie dev moderne — frameworks, outils, IA, conventions de casse. Il oriente la reconnaissance vers les bons termes et réécrit phonétiquement le russe prononcé avec l'orthographe correcte (« тайп скрипт » → TypeScript). Il s'enrichit avec les mises à jour.",
            "Un vocabolario integrato di terminologia dev moderna — framework, strumenti, IA, convenzioni sui nomi. Orienta il riconoscimento verso i termini corretti e riscrive foneticamente il russo pronunciato nella grafia giusta («тайп скрипт» → TypeScript). Cresce con gli aggiornamenti dell'app.",
            "Um vocabulário embutido de terminologia dev moderna — frameworks, ferramentas, IA, convenções de nomenclatura. Direciona o reconhecimento para os termos corretos e reescreve foneticamente o russo falado com a grafia correta («тайп скрипт» → TypeScript). Cresce com as atualizações do app."),
        .tipPersonalDict: r(
            "Your own spoken → written rules: project names, brands, teammates' names. They outrank the built-in dictionary and are applied live while you speak. Everything stays on this Mac.",
            "Твои собственные правила «произносится → печатается»: названия проектов, бренды, имена коллег. Они приоритетнее встроенного словаря и применяются на лету, во время речи. Всё хранится только на этом Mac.",
            "Deine eigenen Regeln „gesprochen → geschrieben“: Projektnamen, Marken, Namen von Kollegen. Sie haben Vorrang vor dem eingebauten Wörterbuch und werden live während des Sprechens angewendet. Alles bleibt auf diesem Mac.",
            "Tus propias reglas «dicho → escrito»: nombres de proyectos, marcas, nombres de colegas. Tienen prioridad sobre el diccionario integrado y se aplican en vivo mientras hablas. Todo queda en este Mac.",
            "Vos propres règles « dit → écrit » : noms de projets, marques, prénoms des collègues. Elles priment sur le dictionnaire intégré et s'appliquent en direct pendant que vous parlez. Tout reste sur ce Mac.",
            "Le tue regole «detto → scritto»: nomi di progetti, brand, nomi dei colleghi. Hanno priorità sul dizionario integrato e si applicano in diretta mentre parli. Tutto resta su questo Mac.",
            "Suas próprias regras «falado → digitado»: nomes de projetos, marcas, nomes de colegas. Têm prioridade sobre o dicionário integrado e são aplicadas ao vivo enquanto você fala. Tudo fica neste Mac."),
        .tipLearn: r(
            "After a live session, BabelBar may read back the field it typed into (via Accessibility) to notice your manual fixes. The same fix seen twice becomes a suggestion below — it never applies automatically. Works only in apps that expose their text fields; nothing is ever stored beyond the suggestion itself.",
            "После живой сессии BabelBar может прочитать поле, в которое печатал (через Универсальный доступ), чтобы заметить твои ручные правки. Одна и та же правка, замеченная дважды, становится подсказкой ниже — автоматически она никогда не применяется. Работает только в приложениях, которые отдают своё текстовое поле; ничего не сохраняется, кроме самой подсказки.",
            "Nach einer Live-Sitzung kann BabelBar das Feld, in das es getippt hat, (über Bedienungshilfen) zurücklesen, um deine manuellen Korrekturen zu bemerken. Dieselbe Korrektur, zweimal gesehen, wird unten zum Vorschlag — automatisch angewendet wird nie etwas. Funktioniert nur in Apps, die ihre Textfelder offenlegen; gespeichert wird nichts außer dem Vorschlag selbst.",
            "Tras una sesión en vivo, BabelBar puede releer el campo en el que escribió (vía Accesibilidad) para detectar tus correcciones manuales. La misma corrección vista dos veces se convierte en una sugerencia abajo — nunca se aplica automáticamente. Funciona solo en apps que exponen sus campos de texto; no se guarda nada más allá de la sugerencia.",
            "Après une séance en direct, BabelBar peut relire le champ dans lequel il a saisi (via Accessibilité) pour repérer vos corrections manuelles. La même correction vue deux fois devient une suggestion ci-dessous — jamais appliquée automatiquement. Ne fonctionne que dans les apps qui exposent leurs champs de texte ; rien n'est stocké au-delà de la suggestion elle-même.",
            "Dopo una sessione in diretta, BabelBar può rileggere il campo in cui ha digitato (tramite Accessibilità) per notare le tue correzioni manuali. La stessa correzione vista due volte diventa un suggerimento qui sotto — non si applica mai automaticamente. Funziona solo nelle app che espongono i loro campi di testo; non viene salvato nulla oltre al suggerimento stesso.",
            "Após uma sessão ao vivo, o BabelBar pode reler o campo em que digitou (via Acessibilidade) para notar suas correções manuais. A mesma correção vista duas vezes virá uma sugestão abaixo — nunca é aplicada automaticamente. Funciona só em apps que expõem seus campos de texto; nada é armazenado além da própria sugestão."),
        .tipFreq: r(
            "Counts how often dictionary terms appear in your dictations and feeds the most used ones back into recognition, so the words you actually work with are recognized with priority.",
            "Считает, как часто термины из словарей встречаются в твоих диктовках, и передаёт самые употребимые обратно в распознавание — слова, с которыми ты реально работаешь, распознаются приоритетно.",
            "Zählt, wie oft Wörterbuchbegriffe in deinen Diktaten vorkommen, und speist die häufigsten in die Erkennung zurück — die Wörter, mit denen du wirklich arbeitest, werden vorrangig erkannt.",
            "Cuenta con qué frecuencia aparecen los términos del diccionario en tus dictados y devuelve los más usados al reconocimiento: las palabras con las que realmente trabajas se reconocen con prioridad.",
            "Compte la fréquence des termes du dictionnaire dans vos dictées et renvoie les plus utilisés à la reconnaissance : les mots avec lesquels vous travaillez vraiment sont reconnus en priorité.",
            "Conta quanto spesso i termini del dizionario compaiono nelle tue dettature e restituisce i più usati al riconoscimento: le parole con cui lavori davvero vengono riconosciute con priorità.",
            "Conta com que frequência os termos do dicionário aparecem nos seus ditados e devolve os mais usados ao reconhecimento: as palavras com as quais você realmente trabalha são reconhecidas com prioridade."),
        .errSpeechDenied: r("Speech Recognition permission is required.",
                            "Нужно разрешение «Распознавание речи».",
                            "Berechtigung „Spracherkennung“ erforderlich.",
                            "Se requiere el permiso de Reconocimiento de voz.",
                            "L’autorisation Reconnaissance vocale est requise.",
                            "È richiesto il permesso Riconoscimento vocale.",
                            "É necessária a permissão de Reconhecimento de Fala."),
        .errSpeechUnavailable: r("Speech recognition is unavailable on this Mac.",
                                 "Распознавание речи недоступно на этом Mac.",
                                 "Spracherkennung ist auf diesem Mac nicht verfügbar.",
                                 "El reconocimiento de voz no está disponible en este Mac.",
                                 "La reconnaissance vocale n’est pas disponible sur ce Mac.",
                                 "Il riconoscimento vocale non è disponibile su questo Mac.",
                                 "O reconhecimento de fala não está disponível neste Mac."),
        .errSpeechOnDevice: r("No on-device model for this language.",
                              "Нет локальной модели для этого языка.",
                              "Kein lokales Modell für diese Sprache.",
                              "No hay modelo local para este idioma.",
                              "Pas de modèle local pour cette langue.",
                              "Nessun modello locale per questa lingua.",
                              "Sem modelo local para este idioma."),
    ]
}
