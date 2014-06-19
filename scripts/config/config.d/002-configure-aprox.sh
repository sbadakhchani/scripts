#!/bin/sh

echo "Creating CI-* / CIx-* auto-proxy rule..."
cat > /opt/aprox/data/autoprox/0010-ci.groovy << 'EOF'
import org.commonjava.aprox.autoprox.data.*;
import java.net.MalformedURLException;
import org.commonjava.aprox.model.*;

class CIRule extends AbstractAutoProxRule
{
    def REGEX = /CI([xX]?)-(.+)/

    boolean matches( String named )
    {
        return named =~ REGEX;
    }

    RemoteRepository createRemoteRepository( String named )
    {
        def match = (named =~ REGEX)[0]
        if ( match[2] == 'loop')
        {
            return null
        }

        RemoteRepository repo = new RemoteRepository( named, "http://koji.localdomain/kojifiles/repos/${match[2]}/latest/maven/" );
        repo.with {
            passthrough= true
            description= "Koji repository for tag: ${match[2]}"
        }

        return repo
    }

    HostedRepository createHostedRepository( String named )
    {
        HostedRepository repo = new HostedRepository( named );
        repo.with {
            allowSnapshots= true
            allowReleases=  true
            description= "CI snapshots for ${named}"
        }

        return repo
    }

    Group createGroup( String named )
    {
        Group g = new Group( named );

        def match = (named =~ REGEX)[0]
        g.addConstituent( new StoreKey( StoreType.remote, named ) )

        def publicPart = ""
        if ( match[1] )
        {
            g.addConstituent( new StoreKey( StoreType.group, "public" ) )
            publicPart = " Also includes the constituents from the 'public' group."
        }

        def repoPart = "."
        if ( match[2] != 'loop')
        {
            g.addConstituent( new StoreKey( StoreType.hosted, named ) )
            repoPart = ", along with a proxy to the Koji maven repository for the tag: '${match[2]}'."
        }

        g.setDescription( "Group containing a local CI snapshot/releases deployment repository${repoPart}${publicPart}" )

        g
    }

}
EOF

echo "Configuring public group to contain central and jboss.org public repository..."
cat > /opt/aprox/data/aprox/group/public.json << 'EOF'
{"constituents":["remote:central","remote:JB-public"],"key":"group:public"}
EOF

echo "Setting up WebDAV mount..."
test -d /etc/davfs || mkdir /etc/davfs
cat > /etc/davfs/secrets << 'EOF'
http://localhost:8090/mavdav/settings koji notused
EOF

mkdir /aprox
chown -R koji:koji /aprox

AUTO_MASTER_LINE='/aprox /etc/auto.aprox'
grep $AUTO_MASTER_LINE /etc/auto.master || echo $AUTO_MASTER_LINE >> /etc/auto.master

cat > /etc/auto.aprox << 'EOF'
settings -fstype=davfs,rw,dir_mode=0777,file_mode=0444 :http://localhost:8090/mavdav/settings
EOF

service aprox restart
service autofs restart

echo "Redirecting default Maven settings.xml for user 'koji' to AProx...\n  ...using local-loop aprox deployment: '/aprox/settings/group/settings-CIx-loop.xml'"
if [ ! -d /home/koji/.m2 ]; then
  mkdir -p /home/koji/.m2
  chown -R koji:koji /home/koji/.m2
fi

KOJI_DEFAULT_SETTINGS_XML="/home/koji/.m2/settings.xml"

if [ -f $KOJI_DEFAULT_SETTINGS_XML ]; then
 mv $KOJI_DEFAULT_SETTINGS_XML ${KOJI_DEFAULT_SETTINGS_XML}.pre-aprox
fi

ln -s /aprox/settings/group/settings-CIx-loop.xml $KOJI_DEFAULT_SETTINGS_XML

echo "AProx configuration complete."

