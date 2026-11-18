import plistlib
import unittest
from pathlib import Path

APP = Path(__file__).resolve().parents[2] / "Hush/Hush"


class EntitlementsTests(unittest.TestCase):
    """Team-signed builds add only the keychain access group to what every build has."""

    def test_team_file_adds_only_the_keychain_group(self):
        base = plistlib.loads((APP / "Hush.entitlements").read_bytes())
        team = plistlib.loads((APP / "Hush-Team.entitlements").read_bytes())
        self.assertEqual(team.pop("keychain-access-groups"), ["$(AppIdentifierPrefix)com.decentralfreedom.hush"])
        self.assertEqual(team, base)


if __name__ == "__main__":
    unittest.main()
