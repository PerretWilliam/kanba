# Kanban

App macOS SwiftUI (`./build.sh`). Données: `~/Library/Application Support/Kanban/boards.json`.
L'app recharge ce fichier en direct (édition manuelle possible). Les outils MCP n'y écrivent PAS: ils écrivent `proposal.json` (base + état proposé), l'app affiche un diff et l'utilisateur valide (tout ou case par case). Seul `select_board` est immédiat.
Serveur MCP `kanban` (`tools/mcp.py`, stdlib, enregistré en scope user: `claude mcp add --scope user kanban -- python3 <chemin>/tools/mcp.py`): get_boards (avec recherche/filtres), add_card, update_card, delete_card, clear_last_column, add_column, update_column, delete_column, add_board (colonnes + cartes initiales = templates), update_board, select_board, delete_board, export_board, import_board — préfère-le à l'édition manuelle.

Format: `{"selected": "<uuid board>", "boards": [Board]}`
- Board: `{id: uuid, name, columns: [{id, name, color}], cards: [Card]}`; couleurs: gray blue green orange purple pink teal red; la dernière colonne = "terminé".
- Card: `{id: uuid (nouveau uuid4 majuscule), title, notes, priority: 0|1|2 (basse/moyenne/haute), due?: nombre de secondes depuis 2001-01-01 UTC, status: id de colonne, tags: [string]}`.
- JSON invalide ou `boards` vide = modification ignorée.
