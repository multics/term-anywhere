#!/usr/bin/env python3
"""Export explicit settings for selected aliases. Never export keys or AWS secrets."""
import argparse, subprocess, json, shlex, uuid
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('aliases',nargs='+');p.add_argument('--output',required=True);p.add_argument('--tmux-session',default='')
a=p.parse_args();hosts=[]
for alias in a.aliases:
    r=subprocess.run(['ssh','-G',alias],capture_output=True,text=True,check=True)
    values={}
    for line in r.stdout.splitlines():
        key,_,value=line.partition(' ');values.setdefault(key,[]).append(value)
    first=lambda key,default='':values.get(key,[default])[0]
    identity=next((x for x in values.get('identityfile',[]) if Path(x).expanduser().is_file()),None)
    if not identity:raise SystemExit(f'{alias}: no referenced identity file exists')
    aws='';region='us-west-2'
    proxy=first('proxycommand')
    if proxy:
        outer=shlex.split(proxy)
        command=shlex.split(outer[2]) if outer[:2]==['sh','-c'] and len(outer)==3 else outer
        if command[:3]!=['aws','ssm','start-session'] or 'AWS-StartSSHSession' not in command:raise SystemExit(f'{alias}: unsupported ProxyCommand')
        aws=command[command.index('--profile')+1];region=command[command.index('--region')+1]
    if first('hostname').startswith('i-') and not aws:raise SystemExit(f'{alias}: instance ID without an SSM proxy; select its canonical alias')
    if first('proxyjump') not in ['', 'none']:raise SystemExit(f'{alias}: ProxyJump is not supported')
    hosts.append(dict(id=str(uuid.uuid5(uuid.NAMESPACE_DNS,'term-anywhere:'+alias)),name=alias,address=first('hostname'),port=int(first('port','22')),username=first('user'),keyID=Path(identity).name,tmuxSession=a.tmux_session,tmuxSocket='',awsProfile=aws,region=region,manualPrefix=''))
out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(hosts,indent=2)+'\n');out.chmod(0o600)
print(f'Exported {len(hosts)} selected hosts to {out}. Private keys and AWS credentials are not included.')
