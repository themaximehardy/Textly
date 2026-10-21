import Foundation

/// Sample texts to try each action on (Settings › Actions › Try it), in several languages.
/// They contain the kind of mistakes and structure each action is meant to handle.
enum ActionExamples {
    struct Example: Identifiable, Hashable {
        let label: String
        let text: String
        /// For Translate: the language to translate into.
        var targetLanguage: String? = nil
        var id: String { label }
    }

    static func examples(for action: TextAction) -> [Example] {
        switch action.builtin {
        case "fix": return fix
        case "improve": return improve
        case "summarise": return summarise
        case "translate": return translate
        default: return general
        }
    }

    // MARK: Fix: real mistakes, informal tone, Franglais to keep

    static let fix: [Example] = [
        Example(label: "French email (Franglais)", text: """
        Salut Paul,

        Je vais check avec l'équipe demain et je te fait un retour rapidement. Le feedback du client etait plutot positif, mais ils veulent qu'on rajoute un export CSV avant le go-live. On peut faire un call jeudi pour en parler ? Je t'envoie l'invit dans la journée.

        Merci encore pour ton aide sur le deck, c'étais top !
        Max
        """),
        Example(label: "English update with typos", text: """
        Hi team,

        Quick update on the launch: we've fixed most of the bugs reported last week, but their still two issues on the checkout page that needs attention. I'll be working on them tommorow morning, and I expect to have a fix by the afternoon.

        Also, could everyone add they're availability for the retro in the shared calendar? Thanks!
        """),
        Example(label: "Spanish message", text: """
        Hola Lucía, te escribo para confirmar la reunion del martes. He revisado el presupuesto y creo que hay algunos errores en las cifras de marketing, tendriamos que hablarlo antes de enviarselo al cliente. ¿Te viene bien a las diez?
        """),
        Example(label: "German note", text: """
        Hallo zusammen, ich habe die Präsentation überarbeitet und die neuen Zahlen eingefügt. Könnt ihr bis morgen einen blick darauf werfen? Ich denke das wir die Folie zum Budget noch kürzen sollten, sie ist im moment zu lang.
        """),
    ]

    // MARK: Improve: clumsy but correct-ish text, some of it list-like

    static let improve: [Example] = [
        Example(label: "Rambling French message", text: """
        Bonjour à tous, alors comme je disais en réunion je pense que ce serait bien qu'on revoie un peu le process d'onboarding parce que là c'est un peu long et les nouveaux clients ils se perdent un peu, du coup il faudrait simplifier le formulaire, ajouter une vidéo de présentation et aussi peut-être envoyer un email de relance au bout de trois jours si jamais ils n'ont pas fini, voilà dites-moi ce que vous en pensez.
        """),
        Example(label: "English proposal", text: """
        So basically what we want to do with this project is to make the checkout faster because at the moment a lot of people are leaving before they pay and we think it's because there are too many steps, so the plan is to remove the account creation step, add Apple Pay and Google Pay, and also show the delivery costs earlier in the process so people are not surprised at the end, and we think this could improve conversion by quite a lot.
        """),
        Example(label: "Spanish email", text: """
        Hola a todos, quería comentaros que el proyecto va bien pero que hay algunas cosas que tenemos que mirar porque si no vamos a tener problemas con el plazo, sobre todo el diseño de la página principal que todavía no está validado y también las traducciones que faltan, entonces os propongo que nos veamos el jueves para verlo todo juntos.
        """),
    ]

    // MARK: Summarise: long texts with decisions and action items

    static let summarise: [Example] = [
        Example(label: "Meeting notes (English)", text: """
        Weekly product meeting, Tuesday

        We started with the Q4 roadmap. Sarah presented the three options for the new pricing page. After some discussion the team agreed to go with option B (three tiers, annual discount of 20%), mainly because it tested best with customers last month. Tom raised a concern that the enterprise tier is still unclear; Sarah will write a one-page description by Friday.

        Next, the mobile app. The iOS release is blocked by the App Store review, which rejected the build because of the login screen. Ahmed thinks it's a quick fix and will resubmit on Wednesday. Android is on track for the 15th.

        Finally, hiring: we have two candidates for the senior designer role. Interviews are scheduled for next Monday and Tuesday. Max will send the case study to both candidates today.

        Next meeting: same time next week. Budget review to be added to the agenda.
        """),
        Example(label: "Long email (French)", text: """
        Bonjour à tous,

        Suite à notre point d'hier avec le client, voici ce qu'il faut retenir. Le client est globalement satisfait de la V1, notamment de la rapidité du site et du nouveau tunnel de commande. En revanche, il trouve que les fiches produits manquent d'informations, en particulier sur la composition et les conseils d'utilisation. Il aimerait aussi pouvoir filtrer les produits par type de peau.

        Côté planning, la V2 doit être livrée le 30 novembre au plus tard, car une campagne marketing est prévue début décembre. Le budget reste le même, mais le client est prêt à financer une option supplémentaire pour les avis clients si on lui envoie un devis avant vendredi.

        Pour la suite : Julie s'occupe de la refonte des fiches produits, Karim regarde la faisabilité du filtre par type de peau, et je prépare le devis pour les avis clients. On refait un point mardi prochain.

        Bonne journée,
        Max
        """),
        Example(label: "Article extract (German)", text: """
        Immer mehr Unternehmen setzen auf die Vier-Tage-Woche. Eine aktuelle Studie mit über 60 Firmen zeigt, dass die Produktivität in den meisten Fällen gleich blieb oder sogar leicht stieg, während die Zahl der Krankheitstage deutlich sank. Die Mitarbeitenden berichteten von weniger Stress und einer besseren Vereinbarkeit von Beruf und Familie. Kritiker weisen jedoch darauf hin, dass das Modell nicht für alle Branchen geeignet ist, etwa im Gesundheitswesen oder im Einzelhandel, wo Schichten abgedeckt werden müssen. Fast alle teilnehmenden Unternehmen wollen das Modell nach der Testphase beibehalten.
        """),
    ]

    // MARK: Translate: tone, idioms and structure to keep

    static let translate: [Example] = [
        Example(label: "French Slack message → English", text: """
        Hello la team ! Petit point rapide : la démo de ce matin s'est super bien passée, le client était ravi 🎉

        Prochaines étapes :
        - envoyer le devis d'ici vendredi
        - caler un call avec leur équipe tech la semaine pro
        - préparer l'onboarding

        On croise les doigts, mais ça sent bon !
        """, targetLanguage: "English (UK)"),
        Example(label: "English email → French", text: """
        Hi Claire,

        Thanks for getting back to me so quickly. I've had a look at the contract and it all looks good, apart from the payment terms: we'd need 30 days rather than 15. Could you check whether that works on your side?

        Happy to jump on a quick call if it's easier.

        Best,
        Max
        """, targetLanguage: "French"),
        Example(label: "English note → Spanish", text: """
        Reminder: the office will be closed on Friday for the team day. We're meeting at 10am at the station, so please don't be late! Lunch is on us, and the afternoon activity is a surprise.
        """, targetLanguage: "Spanish"),
    ]

    // MARK: Your own actions

    static let general: [Example] = [
        Example(label: "Short English email", text: """
        Hi Sam, thanks for sending the proposal over. I've read it and I think it's mostly good, but the timeline looks a bit tight for us and I'm not sure we can get the content ready by the 1st. Could we push the launch by two weeks? Let me know what you think.
        """),
        Example(label: "French message", text: """
        Coucou, je voulais te dire que la présentation d'hier était vraiment top, les clients ont adoré la partie sur les chiffres. Par contre il faudrait qu'on retravaille un peu la fin, c'était un peu long. Tu as un moment demain pour en parler ?
        """),
        Example(label: "Meeting notes", text: """
        Call with Acme: they like the prototype. Concerns: price (too high for small teams), no Slack integration yet. Next: Max sends revised pricing Thursday, Julie checks Slack integration effort, follow-up call next Tuesday.
        """),
    ]
}
