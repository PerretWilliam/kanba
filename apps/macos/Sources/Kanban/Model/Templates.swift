import SwiftUI

/// A starter board: its own columns plus a few example cards (each pointing at a column by index).
struct Template: Identifiable {
    struct Col { var name: String, color: ColumnColor }
    struct Item {
        var title: String, notes = "", col = 0, priority = Priority.medium
        var tags: [String]
        var dueInDays: Int?
    }
    let id: String, name: String, blurb: String, icon: String, color: Color
    let columns: [Col], items: [Item]

    func makeBoard() -> Board {
        let cols = columns.map { Column(name: $0.name, color: $0.color) }
        let cards = items.map { i in
            Card(title: i.title, notes: i.notes, priority: i.priority,
                 due: i.dueInDays.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) },
                 status: cols[min(i.col, cols.count - 1)].id, tags: i.tags)
        }
        return Board(name: name, columns: cols, cards: cards)
    }

    private static let classic: [Col] = [.init(name: "À faire", color: .gray), .init(name: "En cours", color: .blue), .init(name: "Terminé", color: .green)]

    static let all: [Template] = [
        Template(id: "empty", name: "Tableau vide", blurb: "Trois colonnes, aucune carte.", icon: "square.dashed", color: .gray,
                 columns: classic, items: []),
        Template(id: "classic", name: "Kanban classique", blurb: "À faire, en cours, terminé.", icon: "rectangle.split.3x1", color: .blue,
                 columns: classic, items: [
            .init(title: "Définir les objectifs", notes: "Ce qu'on veut livrer et pour quand.", priority: .high, tags: ["cadrage"], dueInDays: 2),
            .init(title: "Premier prototype", col: 1, tags: ["produit"], dueInDays: 6),
            .init(title: "Lire la documentation", priority: .low, tags: ["veille"]),
            .init(title: "Créer le projet", col: 2, tags: ["cadrage"]),
        ]),
        Template(id: "scrum", name: "Projet logiciel", blurb: "Backlog, sprint, revue, livraison.", icon: "hammer", color: .indigo,
                 columns: [.init(name: "Backlog", color: .gray), .init(name: "Sprint", color: .purple), .init(name: "En cours", color: .blue),
                           .init(name: "Revue", color: .orange), .init(name: "Livré", color: .green)], items: [
            .init(title: "Authentification par e-mail", priority: .high, tags: ["feature"]),
            .init(title: "Exporter les données en CSV", priority: .low, tags: ["feature"]),
            .init(title: "Refonte de l'écran d'accueil", col: 1, tags: ["design"], dueInDays: 5),
            .init(title: "Corriger le bug de connexion", col: 2, priority: .high, tags: ["bug"]),
            .init(title: "Ajouter les tests d'intégration", col: 3, tags: ["qualité"]),
            .init(title: "Mettre en place l'intégration continue", col: 4, tags: ["infra"]),
        ]),
        Template(id: "bugs", name: "Suivi de bugs", blurb: "De l'anomalie signalée à la correction.", icon: "ladybug", color: .red,
                 columns: [.init(name: "Signalé", color: .red), .init(name: "Confirmé", color: .orange), .init(name: "En correction", color: .blue),
                           .init(name: "À vérifier", color: .purple), .init(name: "Corrigé", color: .green)], items: [
            .init(title: "Crash au lancement sur macOS 15", priority: .high, tags: ["crash"]),
            .init(title: "Le texte déborde dans la fiche", col: 1, priority: .low, tags: ["ui"]),
            .init(title: "Sauvegarde parfois perdue", col: 2, priority: .high, tags: ["données"]),
            .init(title: "Date d'échéance décalée d'un jour", col: 3, tags: ["dates"]),
            .init(title: "Tooltip manquant", col: 4, priority: .low, tags: ["ui"]),
        ]),
        Template(id: "content", name: "Contenu éditorial", blurb: "Idées, rédaction, relecture, publication.", icon: "megaphone", color: .pink,
                 columns: [.init(name: "Idées", color: .gray), .init(name: "Rédaction", color: .blue), .init(name: "Relecture", color: .orange),
                           .init(name: "Planifié", color: .purple), .init(name: "Publié", color: .green)], items: [
            .init(title: "10 idées d'articles pour la rentrée", priority: .low, tags: ["idées"]),
            .init(title: "Article de lancement", col: 1, priority: .high, tags: ["blog"], dueInDays: 3),
            .init(title: "Newsletter de novembre", col: 2, tags: ["email"], dueInDays: 5),
            .init(title: "Thread sur les coulisses", col: 3, tags: ["social"], dueInDays: 8),
            .init(title: "Page À propos", col: 4, tags: ["site"]),
        ]),
        Template(id: "jobs", name: "Recherche d'emploi", blurb: "Suivre chaque candidature.", icon: "briefcase", color: .teal,
                 columns: [.init(name: "À postuler", color: .gray), .init(name: "Postulé", color: .blue), .init(name: "Entretien", color: .orange),
                           .init(name: "Offre", color: .green), .init(name: "Clos", color: .red)], items: [
            .init(title: "Mettre à jour le CV", priority: .high, tags: ["préparation"], dueInDays: 2),
            .init(title: "Studio de design, Lyon", col: 1, tags: ["design"]),
            .init(title: "Startup fintech, remote", col: 2, priority: .high, tags: ["tech"], dueInDays: 4),
            .init(title: "Agence web, Paris", col: 3, tags: ["web"]),
            .init(title: "Grand groupe, poste senior", col: 4, priority: .low, tags: ["tech"]),
        ]),
        Template(id: "study", name: "Révisions", blurb: "Du cours à la maîtrise.", icon: "graduationcap", color: .purple,
                 columns: [.init(name: "À voir", color: .gray), .init(name: "En révision", color: .orange), .init(name: "Maîtrisé", color: .green)], items: [
            .init(title: "Chapitre 4 : probabilités", priority: .high, tags: ["maths"], dueInDays: 6),
            .init(title: "Fiches d'histoire", col: 1, tags: ["histoire"], dueInDays: 3),
            .init(title: "Vocabulaire anglais", col: 1, priority: .low, tags: ["langues"]),
            .init(title: "Chapitre 3 : dérivées", col: 2, tags: ["maths"]),
        ]),
    ]
}
