import ballerina/http;
import ballerina/file;
import ballerina/log;
import ballerina/compression;
import ballerina/runtime;
import ballerina/mime;
import ballerina/config;
import ballerina/os;
import ballerina/io;

@final string FILE_SEPERATOR = "/";


string zipLocation = getLocation("ARTIFACT_LOCATION");
string unzippedLocation = getLocation("UNZIP_LOCATION");
string docLocation = getLocation("DOC_LOCATION");
string endUrl = "http://localhost:9000/";

endpoint http:Listener apiDocsEP {
    port:4040,
    secureSocket:{
        keyStore:{
            filePath:config:getAsString("CONFIG_KEYSTORE_FILE"),
            password:config:getAsString("CONFIG_KEYSTORE_PASSWORD")
        }
    }
};

endpoint http:Client httpEp {
    url:endUrl,
    keyStore:{
        filePath:config:getAsString("KEYSTORE_PUSH"),
        password:config:getAsString("KEYSTORE_PASSWORD_PUSH")
    }
};

@http:ServiceConfig {
    basePath:"/"
}
service<http:Service> apiDocs bind apiDocsEP {

    @http:ResourceConfig {
        methods:["GET"],
        path:"/*"
    }
    generateAPIDocs (endpoint caller, http:Request req) {
        http:Response res = new;
        var resp = httpEp -> get("/",req);
        match resp {
            http:HttpConnectorError er => {
                log:printInfo(er.message);
                res.setStringPayload(er.message);
                _ = caller -> respond(res);
            }
            http:Response response => {
                if (response.statusCode == 200) {
                    var received = response.getJsonPayload();
                    match received {
                        json payload => {
                            string orgName = payload["orgName"].toString();
                            string packageName = payload["packageName"].toString();
                            string packageVersion = payload["packageVersion"].toString();
                            string rawPath = orgName + FILE_SEPERATOR + packageName + FILE_SEPERATOR + packageVersion;

                            _ = caller -> respond(response);
                            future f = start generateDocs(rawPath, packageName);
                        }
                        mime:EntityError er => {
                            log:printInfo(er.message);
                            res.setStringPayload(er.message);
                            _ = caller -> respond(res);
                        }
                    }
                }

                _ = caller -> respond(response);
            }
        }
    }
}



function getLocation (string locationType) returns (string) {
    string location = config:getAsString(locationType);
    int lengthOfLocation = location.length();
    int lastIndexOfFileSeperator = location.lastIndexOf("/");
    if (lengthOfLocation != lastIndexOfFileSeperator + 1) {
        location = location + "/";
    }
    return location;
}

function createDirectory (string pkgDocVarPath) {
    file:Path pkgDocVarLocation = new (untaint pkgDocVarPath);
    if (!file:exists(pkgDocVarLocation)) {
        var createOrgFlag = file:createDirectory(pkgDocVarLocation);
        match createOrgFlag {
            boolean flag => log:printInfo("Creation of directory " + pkgDocVarPath + " status: " + flag);
            file:IOError err => log:printDebug(err.message);
        }
    }
}

function generateDocs (string rawPath, string packageName) {
    string locationOfDocsForPackage = docLocation + rawPath;
    string locationOfUnzipForPackage = unzippedLocation + rawPath;
    string locationOfZipForPackage = zipLocation + rawPath;
    string unzippedPackageLocation = locationOfUnzipForPackage + "/" + packageName;

    createDirectory(locationOfDocsForPackage);
    // check whether docs already generated
    string pkgDocPath = locationOfDocsForPackage + "/api-docs";
    file:Path pkgDocLocation = new (untaint pkgDocPath);
    if (!file:exists(pkgDocLocation)) {

        //check whether package already unzipped
        file:Path unzippedPkgPath = new (untaint unzippedPackageLocation);
        if (!file:exists(unzippedPkgPath)) {
            createDirectory(unzippedPackageLocation);
            file:Path srcPath = new (untaint locationOfZipForPackage + "/" + packageName + ".zip");
            file:Path destPath = new (untaint unzippedPackageLocation);
            var result = compression:decompress(srcPath, destPath);
            match result {
                compression:CompressionError err => log:printErrorCause(err.message,err);
                () => log:printInfo("Decompressed " + packageName + ".zip successfully");
            }
        }
        string execMessage = runtime:execBallerina("doc", "-o " + pkgDocPath + " --sourceroot " +
                                                          locationOfUnzipForPackage + "/ " +
                                                          packageName + " -e generateToc=true");
        log:printInfo(execMessage);
    }
}