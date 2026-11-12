# GTA MOD : vehicle_settings

Modifie les paramètres du véhicule dans lequel se trouve le joueur : couleurs, vitesse, adhérence, indestructibilité.

## Fonctionnalités

Menu « Vehicle Settings » (touche **F1**) :

- **Color 1 / Color 2** : couleurs principale et secondaire du véhicule (ID de 0 à 160), appliquées en direct ; maintenir la flèche gauche/droite fait défiler les couleurs rapidement
- **Speed** : multiplicateur de 1 (valeurs d'origine) à 10, saisi au clavier après avoir appuyé sur Entrée ; il augmente la puissance, la boîte de vitesses, le freinage et l'adhérence des pneus (l'adhérence augmente un peu plus vite que la puissance, pour éviter que le véhicule glisse)
- **Indestructible** : le véhicule ne subit plus de dégâts
- **Reset** : remet le véhicule à ses valeurs d'origine
- **Close** : ferme le menu

Les réglages sont réappliqués automatiquement quand le joueur monte dans un autre véhicule.

## Prérequis

- Serveur FiveM à jour avec accès admin
- Ressource [MenuV](https://github.com/MenuV/MenuV) installée et démarrée avant ce mod

## Installation

1. Télécharge ce dépôt et renomme le dossier `gtamod-vehicle-settings` en `vehicle_settings`
2. Copie le dossier `vehicle_settings` dans `resources/`
3. Ajoute `ensure menuv` puis `ensure vehicle_settings` dans ton `server.cfg`
4. Redémarre le serveur

## Utilisation

Monte dans un véhicule, appuie sur **F1** pour ouvrir le menu, puis règle les couleurs, la vitesse ou la protection.

> Le mod `change_ped` utilise aussi la touche **F1** : si les deux sont démarrés en même temps, change la touche de l'un des deux dans son `client.lua`.

## Structure du dossier

```
vehicle_settings/
├─ client.lua           -- script principal (menu MenuV, couleurs, vitesse, protection)
├─ fxmanifest.lua
└─ README.md
```

## Crédits

Tuto et mod réalisés par :
Armand POPOT & Alice MASSART, PAD EMD 2026.
