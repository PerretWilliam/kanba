import SwiftUI

/// A starter board: a set of cards spread over the three fixed columns.
struct Template: Identifiable {
    struct Item {
        var title: String, notes = "", status = Status.todo, priority = Priority.medium
        var tags: [String] = [], dueInDays: Int?
    }
    let id: String, name: String, blurb: String, icon: String, color: Color, items: [Item]

    func makeCards() -> [Card] {
        items.map { i in
            Card(title: i.title, notes: i.notes, priority: i.priority,
                 due: i.dueInDays.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) },
                 status: i.status, tags: i.tags)
        }
    }

    static let all: [Template] = [
        Template(id: "empty", name: "Tableau vide", blurb: "Repartir de zéro.", icon: "square.dashed", color: .gray, items: []),
        Template(id: "software", name: "Projet logiciel", blurb: "Sprint, bugs et livraison.", icon: "hammer", color: .blue, items: [
            .init(title: "Définir le périmètre du sprint", notes: "Objectifs et critères d'acceptation.", priority: .high, tags: ["sprint"], dueInDays: 2),
            .init(title: "Maquettes de l'écran d'accueil", status: .doing, tags: ["design"], dueInDays: 5),
            .init(title: "Corriger le bug de connexion", status: .doing, priority: .high, tags: ["bug"]),
            .init(title: "Écrire les tests d'intégration", priority: .low, tags: ["qualité"], dueInDays: 9),
            .init(title: "Mettre en place l'intégration continue", status: .done, tags: ["infra"]),
        ]),
        Template(id: "personal", name: "Personnel", blurb: "Tâches du quotidien et projets perso.", icon: "house", color: .orange, items: [
            .init(title: "Faire les courses", priority: .low, tags: ["maison"], dueInDays: 1),
            .init(title: "Prendre rendez-vous chez le dentiste", tags: ["santé"], dueInDays: 7),
            .init(title: "Préparer le voyage", notes: "Billets, hébergement, itinéraire.", status: .doing, tags: ["voyage"], dueInDays: 21),
            .init(title: "Payer les impôts", status: .done, priority: .high, tags: ["admin"]),
        ]),
        Template(id: "content", name: "Contenu & marketing", blurb: "Idées, rédaction, publication.", icon: "megaphone", color: .pink, items: [
            .init(title: "Brainstorm de 10 idées d'articles", priority: .low, tags: ["idées"]),
            .init(title: "Rédiger l'article de lancement", status: .doing, priority: .high, tags: ["rédaction"], dueInDays: 3),
            .init(title: "Planifier la newsletter", tags: ["email"], dueInDays: 6),
            .init(title: "Publier sur les réseaux", status: .done, tags: ["social"]),
        ]),
        Template(id: "jobs", name: "Recherche d'emploi", blurb: "Suivre ses candidatures.", icon: "briefcase", color: .teal, items: [
            .init(title: "Mettre à jour le CV", priority: .high, tags: ["préparation"], dueInDays: 2),
            .init(title: "Postuler chez une entreprise", tags: ["candidature"]),
            .init(title: "Entretien technique", notes: "Revoir les bases et préparer des questions.", status: .doing, priority: .high, tags: ["entretien"], dueInDays: 4),
            .init(title: "Relancer après entretien", status: .done, priority: .low, tags: ["suivi"]),
        ]),
        Template(id: "study", name: "Études", blurb: "Cours, révisions et examens.", icon: "graduationcap", color: .purple, items: [
            .init(title: "Fiches de révision du chapitre 3", tags: ["révision"], dueInDays: 5),
            .init(title: "Rendre le devoir de groupe", status: .doing, priority: .high, tags: ["devoir"], dueInDays: 2),
            .init(title: "Lire le chapitre 4", priority: .low, tags: ["lecture"]),
            .init(title: "Examen blanc", status: .done, tags: ["examen"]),
        ]),
    ]
}
