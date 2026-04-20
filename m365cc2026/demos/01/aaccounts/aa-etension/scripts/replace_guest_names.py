#!/usr/bin/env python3
import csv
import random
import sys

CSV_PATH = sys.argv[1] if len(sys.argv) > 1 else 'guests-sample.csv'

names = [
"Olivia Smith","Liam Johnson","Emma Williams","Noah Brown","Ava Jones","Oliver Garcia","Sophia Miller","Elijah Davis","Isabella Rodriguez","Lucas Martinez",
"Mia Hernandez","Mason Lopez","Amelia Gonzalez","Logan Wilson","Harper Anderson","James Thomas","Evelyn Taylor","Benjamin Moore","Charlotte Martin","Jacob Lee",
"Abigail Perez","Michael Thompson","Emily White","Daniel Harris","Ella Sanchez","Henry Clark","Scarlett Ramirez","Alexander Lewis","Grace Robinson","Ethan Walker",
"Victoria Young","Matthew Allen","Zoe King","Samuel Wright","Chloe Scott","Jackson Torres","Lily Nguyen","Sebastian Hill","Aurora Flores","Carter Green",
"Penelope Adams","Owen Nelson","Nora Baker","Caleb Rivera","Aria Hall","Wyatt Allen","Lucy Bennett","Julian Carter","Mila Mitchell","Hudson Roberts",
"Ellie Phillips","Levi Campbell","Hannah Parker","Mateo Evans","Violet Edwards","Asher Collins","Stella Stewart","Gabriel Sanchez","Isla Morris","Theodore Rogers",
"Sadie Reed","Anthony Cook","Claire Morgan","Christian Bell","Ruby Murphy","Josiah Bailey","Alice Cooper","Miles Richardson","Peyton Cox","Aaron Howard",
"Lillian Ward","Dominic Brooks","Hazel Kelly","Tristan Sanders","Eleanor Price","Nolan Bennett","Lydia Barnes","Ian Powell","Maya Long","Cooper Patterson",
"Valentina Hughes","Roman Flores","Eliza Fisher","Naomi Gonzales","Blake Simmons","Cora Foster","Julian Webb","Adeline West","Rowan Griffin","Clara Ortiz",
"Everett Stone","Josephine Boyd","Zachary Hunter","Madeline Reynolds","Silas Knight","Vivian Marshall","Elias Bryant","Sienna Lyons","Theo Bishop","Camila Graham",
"Damian Stevens","Iris Perkins","Felix Reynolds","Ember Palmer","Wesley Grant","Josie Porter","Arthur Dean","Mabel Ellis","Hugo Wallace","Eden Matthews",
"Micah Norris","Lila Gilbert","Kaden Weaver","Juniper Lowe","Matteo Fox","Daphne Warren","Phoenix Russell","Sabrina Bowen","Jonah Hicks","Anastasia Hopkins",
"Heath Armstrong","Wren Pierce","Beckett Bryant","Rafael Burns","Delilah Hale","Bennett Moran","Marley Carr","Griffin Norton","Tessa Holt","Kendrick Baldwin",
"Remi Cross","Lyla Banks","Zeke Parrish","Margo Castillo","Kieran Boone","Ophelia Cline","Enzo Hale","Simone Castillo","Arlo Finch","Corinne Doyle",
"Desmond Phelps","Malia Kemp","Lennox Santana","Priya Vasquez","Callum Ortega","Zara Ochoa","Camryn Hodge","Ellis Roy","Sabrina Mendez","Holden Foley",
"Mara Fuentes","Beck Avery","Amaya Pruitt","Poppy McKenzie","Dalton Mccoy","Felicity Joyce","Sloane Brennan","Leonora Sheppard","Cole Mclean","Nia Duran",
"Otto Kaiser","Mavis Calderon","Cyrus Kirby","Alina Holloway","Jace Christian","Talia Rocha","Blake Odom","Yara Cardenas","Keira Mays","Abram Trevino",
"Liana Hood","Archer Mullen","Farrah Juarez","Eamon Lang","Harlan McIntyre","Ramona Velez","Troy Sanford","Lucian Sweet","Norah Bird","Lucia Branch",
"Dorian Brady","Elsie Mckee","Caspian Hardin","Zaira Mccullough","Reed Mccarthy","Leland Burch","Keegan Patrick","Sienna Galloway","Holden Foley2","Mabel Parson"
]

# Ensure we have enough names; if not, extend by shuffling repeats
random.shuffle(names)

with open(CSV_PATH, newline='', encoding='utf-8') as f:
    reader = list(csv.DictReader(f))

names_iter = iter(names)
updated = 0
for row in reader:
    display = row.get('DisplayName','')
    if isinstance(display, str) and display.strip().startswith('Guest'):
        try:
            row['DisplayName'] = next(names_iter)
        except StopIteration:
            # reshuffle and continue
            random.shuffle(names)
            names_iter = iter(names)
            row['DisplayName'] = next(names_iter)
        updated += 1

# write back (preserve column order)
fieldnames = reader[0].keys() if reader else ['Domain','SponsorUPN','DisplayName','Email']
with open(CSV_PATH, 'w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(reader)

print(f"Updated {updated} rows in {CSV_PATH}")
