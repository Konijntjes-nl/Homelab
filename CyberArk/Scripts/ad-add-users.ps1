# Load Active Directory module
Import-Module ActiveDirectory

# Set your domain base (update as needed)
$domainBase = "DC=cybermark,DC=lam"  # <-- Replace with your actual domain
$employeeOU = "OU=Employee,$domainBase"
$starWarsOU = "OU=Star Wars,$employeeOU"
$lotrOU = "OU=Lord of the rings,$employeeOU"

# Create Organizational Units
New-ADOrganizationalUnit -Name "Employee" -Path $domainBase -ErrorAction SilentlyContinue
New-ADOrganizationalUnit -Name "Star Wars" -Path $employeeOU -ErrorAction SilentlyContinue
New-ADOrganizationalUnit -Name "Lord of the rings" -Path $employeeOU -ErrorAction SilentlyContinue

# Popular Star Wars names
$starWarsNames = @(
    "Luke", "Leia", "Han", "Chewbacca", "Yoda", "Vader", "Anakin", "ObiWan", "Padme", "Rey",
    "Finn", "Poe", "Kylo", "Palpatine", "Lando", "Jabba", "Grievous", "Dooku", "Maul", "Tarkin",
    "Boba", "Jango", "Ahsoka", "Mace", "QuiGon", "Ezra", "Hera", "Sabine", "Kanan", "Thrawn",
    "Wedge", "Biggs", "Cassian", "Jyn", "Saw", "Chirrut", "Baze", "BoKatan", "Din", "Grogu",
    "Snoke", "Zeb", "Tech", "Echo", "Hunter", "Crosshair", "Omega", "CadBane", "Fennec", "Hux"
)

# Popular Lord of the Rings names
$lotrNames = @(
    "Frodo", "Samwise", "Gandalf", "Aragorn", "Legolas", "Gimli", "Boromir", "Pippin", "Merry", "Gollum",
    "Sauron", "Elrond", "Galadriel", "Saruman", "Theoden", "Eowyn", "Faramir", "Bilbo", "Thranduil", "Arwen",
    "Eomer", "Denethor", "Treebeard", "Shelob", "Radagast", "Haldir", "Lurtz", "Isildur", "Beregond", "Glorfindel",
    "Grima", "Balrog", "Rosie", "Deagol", "Bard", "Bain", "Dwalin", "Bofur", "Bombur", "Oin",
    "Gloin", "Kili", "Fili", "Beorn", "Azog", "Bolg", "Smaug", "Thorin", "Brand", "Drogo"
)

# Create users in Star Wars OU
for ($i = 0; $i -lt 50; $i++) {
    $name = $starWarsNames[$i % $starWarsNames.Count]
    $username = "SW_" + $name + "_" + $i
    New-ADUser -Name $name -SamAccountName $username -UserPrincipalName "$username@cybermark.lab" `
        -Path $starWarsOU -AccountPassword (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force) `
        -Enabled $true -GivenName $name -Surname "Skywalker" -DisplayName $name
}

# Create users in Lord of the Rings OU
for ($i = 0; $i -lt 50; $i++) {
    $name = $lotrNames[$i % $lotrNames.Count]
    $username = "LOTR_" + $name + "_" + $i
    New-ADUser -Name $name -SamAccountName $username -UserPrincipalName "$username@cybermark.lab" `
        -Path $lotrOU -AccountPassword (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force) `
        -Enabled $true -GivenName $name -Surname "Baggins" -DisplayName $name