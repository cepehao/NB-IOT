function hex=configSha256(cfg)
%CONFIGSHA256 Hash a run configuration independently of its output location.
if isfield(cfg,'logging') && isfield(cfg.logging,'outputFolder')
    cfg.logging.outputFolder='<case-output>';
end
bytes=unicode2native(jsonencode(cfg),'UTF-8');
digest=java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(uint8(bytes(:)),'int8'));
hex=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
