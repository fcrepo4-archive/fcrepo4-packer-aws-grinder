#! /bin/bash

echo "from twisted.internet.defer import succeed"
echo ""
echo "class LandscapeLink(object):"
echo "  def register(self, sysinfo):"
echo "    self._sysinfo = sysinfo"
echo "  def run(self):"
echo "    self._sysinfo.add_footnote("
echo "      \"This is an AWS Grinder ${GRINDER_TYPE^} (built with Packer.io)\n    Learn more at http://github.com/ksclarke/packer-aws-grinder\")"
echo "    return succeed(None)"
